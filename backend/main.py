"""
API principal. Expone /buscar, el endpoint central de la app:

1. Busca coincidencia exacta (nombre, SKU o código de barras) en la
   base local SQLite.
2. Si no hay coincidencia exacta, usa Gemini para extraer el principio
   activo de la consulta en lenguaje natural del usuario.
3. Con el producto (o el principio activo detectado por IA) consulta al
   scraper la disponibilidad real/simulada en la sucursal
   "Arbolitos, San Cristóbal" (stock e imagen).
4. Si el stock resultante es 0, busca y devuelve alternativas
   terapéuticas: otros productos con el mismo principio activo que sí
   tengan stock.
5. Enriquece el producto principal y cada alternativa con una foto real
   tomada del catálogo público de Farmatodo Venezuela (vía
   scraper_service), sin importar si la búsqueda llegó por nombre, SKU,
   código de barras o principio activo resuelto por IA. Si Farmatodo no
   responde, cada producto conserva su imagen local sin romper la
   respuesta.
"""

import logging
import os
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func
from sqlalchemy.orm import Session

import ai_resolver
import scraper
import scraper_service
from database import Producto, SessionLocal, get_db, init_db

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("main")

# Código de acceso compartido: obligatorio solo cuando el backend está
# expuesto a Internet (p. ej. desplegado en Render). En uso local en la
# Wi-Fi de la tienda, si no defines APP_ACCESS_KEY, no se pide nada -se
# mantiene el comportamiento original-. Definida, cada consulta debe
# traer el header "X-App-Key" con el mismo valor, o se rechaza con 401.
APP_ACCESS_KEY = os.getenv("APP_ACCESS_KEY")


def verificar_acceso(x_app_key: Optional[str] = Header(default=None)) -> None:
    if APP_ACCESS_KEY and x_app_key != APP_ACCESS_KEY:
        raise HTTPException(status_code=401, detail="Código de acceso inválido o faltante.")

app = FastAPI(
    title="API Farmacia - Stock, Información Médica y Alternativas",
    description=(
        "Backend para consulta de stock, ubicación en planograma y "
        "alternativas terapéuticas por principio activo."
    ),
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup() -> None:
    init_db()
    logger.info("Base de datos inicializada.")


# --------------------------------------------------------------------------
# Esquemas de respuesta
# --------------------------------------------------------------------------


class ProductoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    sku: str
    codigo_barras: Optional[str] = None
    nombre: str
    principio_activo: str
    categoria: Optional[str] = None
    descripcion: Optional[str] = None
    precio: float
    stock: int
    ubicacion_planograma: str
    sucursal: str
    imagen_url: Optional[str] = None
    imagen_referencial: bool = False


class InfoSucursalOut(BaseModel):
    sucursal: str
    disponible: bool
    cantidad: int
    imagen_url: Optional[str] = None
    fuente: str
    desde_cache: bool = False


class BuscarResponse(BaseModel):
    encontrado: bool
    origen: str  # "base_local" | "ia_gemini"
    producto: Optional[ProductoOut] = None
    info_sucursal: Optional[InfoSucursalOut] = None
    principio_activo_detectado: Optional[str] = None
    alternativas: List[ProductoOut] = []
    mensaje: Optional[str] = None


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------


@app.get("/", tags=["salud"])
def salud() -> dict:
    return {"status": "ok", "servicio": "API Farmacia"}


@app.get("/cache/estadisticas", tags=["salud"], dependencies=[Depends(verificar_acceso)])
def estadisticas_cache() -> dict:
    """Aciertos/fallos de los cachés de IA y scraping -útil para
    confirmar en producción que el caché de 30 min realmente está
    evitando llamadas repetidas a Gemini y al scraper-."""
    return {
        "ia": ai_resolver.estadisticas_cache(),
        "scraper": scraper.estadisticas_cache(),
    }


@app.get(
    "/productos",
    response_model=List[ProductoOut],
    tags=["productos"],
    dependencies=[Depends(verificar_acceso)],
)
def listar_productos(db: Session = Depends(get_db)) -> List[Producto]:
    return db.query(Producto).order_by(Producto.nombre).all()


@app.get(
    "/productos/{sku}",
    response_model=ProductoOut,
    tags=["productos"],
    dependencies=[Depends(verificar_acceso)],
)
def obtener_producto(sku: str, db: Session = Depends(get_db)) -> Producto:
    producto = db.query(Producto).filter(func.lower(Producto.sku) == sku.lower()).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    return producto


def _buscar_alternativas(
    db: Session, principio_activo: str, sku_excluir: Optional[str]
) -> List[Producto]:
    query = db.query(Producto).filter(
        func.lower(Producto.principio_activo) == principio_activo.lower(),
        Producto.stock > 0,
    )
    if sku_excluir:
        query = query.filter(Producto.sku != sku_excluir)
    return query.order_by(Producto.stock.desc()).all()


async def _enriquecer_con_fotos_reales(
    producto_out: ProductoOut, alternativas_out: List[ProductoOut]
) -> tuple[ProductoOut, List[ProductoOut]]:
    """Sustituye `imagen_url` por una foto real de Farmatodo cuando se
    encuentra una, buscando el producto principal y todas las
    alternativas EN PARALELO (una sola espera de red, no una por
    producto). Ante cualquier fallo, devuelve los productos sin tocar:
    esto es un enriquecimiento visual, nunca debe romper /buscar."""
    try:
        nombres = [producto_out.nombre] + [a.nombre for a in alternativas_out]
        fotos_por_nombre = await scraper_service.obtener_imagenes_productos(nombres)
    except Exception as exc:  # noqa: BLE001 - el enriquecimiento nunca debe tumbar el endpoint
        logger.warning("No se pudo enriquecer con fotos reales de Farmatodo: %s", exc)
        return producto_out, alternativas_out

    def _con_foto_real(p: ProductoOut) -> ProductoOut:
        foto = fotos_por_nombre.get(p.nombre)
        if not foto:
            return p
        return p.model_copy(update={"imagen_url": foto, "imagen_referencial": True})

    return _con_foto_real(producto_out), [_con_foto_real(a) for a in alternativas_out]


@app.get(
    "/buscar",
    response_model=BuscarResponse,
    tags=["buscar"],
    dependencies=[Depends(verificar_acceso)],
)
async def buscar(
    q: str = Query(..., min_length=2, description="Nombre, SKU o descripción libre del medicamento"),
    db: Session = Depends(get_db),
) -> BuscarResponse:
    consulta = q.strip()
    consulta_norm = consulta.lower()

    # 1. Coincidencia exacta en base local (por nombre, SKU o código de
    #    barras -este último es lo que llega cuando la búsqueda se
    #    disparó desde el escáner de la app-).
    producto = (
        db.query(Producto)
        .filter(
            (func.lower(Producto.nombre) == consulta_norm)
            | (func.lower(Producto.sku) == consulta_norm)
            | (Producto.codigo_barras == consulta)
        )
        .first()
    )

    origen = "base_local"
    principio_activo_detectado: Optional[str] = None

    if producto is not None:
        principio_activo_detectado = producto.principio_activo
    else:
        # 2. Sin coincidencia exacta -> resolver principio activo con IA.
        origen = "ia_gemini"
        info_ia = ai_resolver.extraer_info_medicamento(consulta)
        principio_activo_detectado = info_ia.get("principio_activo")

        if info_ia.get("error"):
            logger.warning("ai_resolver: %s", info_ia["error"])

        if principio_activo_detectado:
            producto = (
                db.query(Producto)
                .filter(func.lower(Producto.principio_activo) == principio_activo_detectado.lower())
                .order_by(Producto.stock.desc())
                .first()
            )

    if producto is None:
        return BuscarResponse(
            encontrado=False,
            origen=origen,
            producto=None,
            info_sucursal=None,
            principio_activo_detectado=principio_activo_detectado,
            alternativas=[],
            mensaje=(
                "No se encontró el medicamento en la base local ni coincidencias "
                "por principio activo a partir de la consulta."
            ),
        )

    # 3. Consultar disponibilidad real/simulada en la sucursal Arbolitos.
    info_sucursal_dict = await scraper.obtener_stock_sucursal(producto.sku, producto.nombre)
    info_sucursal = InfoSucursalOut(**info_sucursal_dict)

    # 4. Si el stock (de sucursal o local) es cero, buscar alternativas.
    stock_efectivo = info_sucursal.cantidad if info_sucursal.disponible else 0
    alternativas: List[Producto] = []
    if stock_efectivo == 0 or producto.stock == 0:
        alternativas = _buscar_alternativas(db, producto.principio_activo, producto.sku)

    producto_out = ProductoOut.model_validate(producto)
    alternativas_out = [ProductoOut.model_validate(a) for a in alternativas]

    # 5. Enriquecer con fotos reales del catálogo de Farmatodo.
    producto_out, alternativas_out = await _enriquecer_con_fotos_reales(producto_out, alternativas_out)

    return BuscarResponse(
        encontrado=True,
        origen=origen,
        producto=producto_out,
        info_sucursal=info_sucursal,
        principio_activo_detectado=principio_activo_detectado,
        alternativas=alternativas_out,
        mensaje=None,
    )
