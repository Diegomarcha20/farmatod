"""
API principal. Expone /buscar, el endpoint central de la app:

1. Busca coincidencia EXACTA (nombre, SKU o código de barras) en la
   base local SQLite. Si hay una, es la respuesta -sin ambigüedad-.
2. Si no hay coincidencia exacta, busca coincidencias PARCIALES por
   nombre, principio activo o descripción (p. ej. "Paracetamol" o
   "alergia" encuentran algo aunque no sea el nombre completo). Esto
   no depende de IA: es rápido y funciona aunque Gemini falle.
3. Si tampoco hay ninguna coincidencia parcial, usa Gemini para
   interpretar la consulta libre (síntoma, descripción vaga) y extraer
   un principio activo probable, y reintenta la búsqueda parcial con
   ese principio activo.
4. Si en cualquiera de los pasos 2-3 hay MÁS DE UNA coincidencia, se
   devuelven todas como `opciones` para que el usuario elija -en vez de
   adivinar una-. Si hay exactamente una, se trata igual que una
   coincidencia exacta (sigue a los pasos 5-7).
5. Con el producto ya confirmado, consulta al scraper la disponibilidad
   real/simulada en la sucursal "Arbolitos, San Cristóbal" (stock e
   imagen). Si el stock resultante es 0, busca y devuelve alternativas
   terapéuticas: otros productos con el mismo principio activo que sí
   tengan stock.
6. Completa la ficha médica (descripción de para qué sirve, país de
   origen del laboratorio) con Gemini SOLO si al catálogo local le
   falta ese dato -para el catálogo de ejemplo no debería activarse,
   ya viene completo; es la red de seguridad para catálogos reales
   incompletos-.
7. Enriquece el producto (u opciones) con una foto real tomada del
   catálogo público de Farmatodo Venezuela (vía scraper_service), sin
   importar cómo se llegó a la coincidencia. Si Farmatodo no responde,
   cada producto conserva su imagen local sin romper la respuesta.
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
    laboratorio: Optional[str] = None
    pais_origen: Optional[str] = None
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
    # Se llena cuando la búsqueda encontró VARIAS coincidencias posibles
    # (por nombre, principio activo o síntoma) y ninguna es claramente
    # LA respuesta -el usuario debe elegir una-. Cuando `opciones` no
    # está vacío, `producto` es null y no hay info_sucursal/alternativas
    # todavía (eso se resuelve en una segunda búsqueda, por el SKU
    # exacto de la opción elegida).
    opciones: List[ProductoOut] = []
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


def _buscar_candidatos(db: Session, termino: str) -> List[Producto]:
    """Coincidencias PARCIALES por nombre, principio activo o
    descripción (case-insensitive, substring) -esto es lo que permite
    encontrar "Paracetamol" sin escribir el nombre completo, o
    "alergia" si esa palabra aparece en alguna descripción-, sin pasar
    por IA para nada."""
    termino_norm = termino.strip().lower()
    if not termino_norm:
        return []
    patron = f"%{termino_norm}%"
    return (
        db.query(Producto)
        .filter(
            func.lower(Producto.nombre).like(patron)
            | func.lower(Producto.principio_activo).like(patron)
            | func.lower(Producto.descripcion).like(patron)
        )
        .order_by(Producto.nombre)
        .all()
    )


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


def _completar_ficha_medica(producto_out: ProductoOut) -> ProductoOut:
    """Rellena `descripcion` y `pais_origen` con Gemini SOLO si el
    catálogo local no los trae -para este catálogo de ejemplo no
    debería activarse nunca, ya viene completo; es la red de seguridad
    para cuando se cargue un catálogo real con datos incompletos-. Se
    llama únicamente sobre el producto ya confirmado (no por cada
    opción de una lista), para no multiplicar llamadas a la IA."""
    actualizaciones: dict = {}

    if not producto_out.descripcion:
        descripcion = ai_resolver.generar_descripcion(producto_out.nombre, producto_out.principio_activo)
        if descripcion:
            actualizaciones["descripcion"] = descripcion

    if producto_out.laboratorio and not producto_out.pais_origen:
        origen = ai_resolver.identificar_origen_laboratorio(producto_out.laboratorio)
        if origen:
            actualizaciones["pais_origen"] = origen

    return producto_out.model_copy(update=actualizaciones) if actualizaciones else producto_out


async def _enriquecer_lista_con_fotos_reales(productos_out: List[ProductoOut]) -> List[ProductoOut]:
    """Sustituye `imagen_url` por una foto real de Farmatodo cuando se
    encuentra una, buscando TODOS los productos de la lista EN
    PARALELO (una sola espera de red, no una por producto). Ante
    cualquier fallo, devuelve los productos sin tocar: esto es un
    enriquecimiento visual, nunca debe romper /buscar."""
    if not productos_out:
        return productos_out

    try:
        nombres = [p.nombre for p in productos_out]
        fotos_por_nombre = await scraper_service.obtener_imagenes_productos(nombres)
    except Exception as exc:  # noqa: BLE001 - el enriquecimiento nunca debe tumbar el endpoint
        logger.warning("No se pudo enriquecer con fotos reales de Farmatodo: %s", exc)
        return productos_out

    def _con_foto_real(p: ProductoOut) -> ProductoOut:
        foto = fotos_por_nombre.get(p.nombre)
        if not foto:
            return p
        return p.model_copy(update={"imagen_url": foto, "imagen_referencial": True})

    return [_con_foto_real(p) for p in productos_out]


async def _enriquecer_con_fotos_reales(
    producto_out: ProductoOut, alternativas_out: List[ProductoOut]
) -> tuple[ProductoOut, List[ProductoOut]]:
    enriquecidos = await _enriquecer_lista_con_fotos_reales([producto_out, *alternativas_out])
    return enriquecidos[0], enriquecidos[1:]


@app.get(
    "/buscar",
    response_model=BuscarResponse,
    tags=["buscar"],
    dependencies=[Depends(verificar_acceso)],
)
async def buscar(
    q: str = Query(
        ...,
        min_length=2,
        description="Nombre completo o parcial, SKU, código de barras, o síntoma/descripción libre",
    ),
    db: Session = Depends(get_db),
) -> BuscarResponse:
    consulta = q.strip()
    consulta_norm = consulta.lower()

    # 1. Coincidencia EXACTA en base local (por nombre, SKU o código de
    #    barras -este último es lo que llega cuando la búsqueda se
    #    disparó desde el escáner de la app-). Si la hay, no hay
    #    ambigüedad posible: es la respuesta.
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
    candidatos: List[Producto] = []

    if producto is None:
        # 2. Sin coincidencia exacta -> coincidencias PARCIALES por
        #    nombre, principio activo o descripción. No depende de IA.
        candidatos = _buscar_candidatos(db, consulta)

        if not candidatos:
            # 3. Ni exacta ni parcial -> resolver con Gemini a partir de
            #    la consulta libre (síntoma, descripción vaga), y
            #    reintentar la búsqueda parcial con el principio activo
            #    que haya sugerido.
            origen = "ia_gemini"
            info_ia = ai_resolver.extraer_info_medicamento(consulta)
            principio_activo_detectado = info_ia.get("principio_activo")

            if info_ia.get("error"):
                logger.warning("ai_resolver: %s", info_ia["error"])

            if principio_activo_detectado:
                candidatos = _buscar_candidatos(db, principio_activo_detectado)

        if len(candidatos) == 1:
            # Una sola coincidencia parcial no es ambigua: se trata
            # igual que una coincidencia exacta.
            producto = candidatos[0]
            candidatos = []

    if producto is not None:
        principio_activo_detectado = producto.principio_activo

    if producto is None and not candidatos:
        return BuscarResponse(
            encontrado=False,
            origen=origen,
            producto=None,
            info_sucursal=None,
            principio_activo_detectado=principio_activo_detectado,
            opciones=[],
            alternativas=[],
            mensaje=(
                "No se encontró el medicamento en la base local ni coincidencias "
                "por nombre, principio activo o síntoma a partir de la consulta."
            ),
        )

    if candidatos:
        # 4. Varias coincidencias posibles: se devuelven todas como
        #    opciones para que el usuario elija -sin adivinar cuál es-.
        #    No se consulta stock de sucursal aquí todavía (eso pasa en
        #    la segunda búsqueda, por el SKU exacto de la elegida).
        opciones_out = await _enriquecer_lista_con_fotos_reales(
            [ProductoOut.model_validate(c) for c in candidatos]
        )
        return BuscarResponse(
            encontrado=True,
            origen=origen,
            producto=None,
            info_sucursal=None,
            principio_activo_detectado=principio_activo_detectado,
            opciones=opciones_out,
            alternativas=[],
            mensaje=f"Se encontraron {len(opciones_out)} coincidencias, elige una.",
        )

    # 5. Coincidencia única y confirmada -> disponibilidad real/simulada
    #    en la sucursal Arbolitos.
    info_sucursal_dict = await scraper.obtener_stock_sucursal(producto.sku, producto.nombre)
    info_sucursal = InfoSucursalOut(**info_sucursal_dict)

    # Si el stock (de sucursal o local) es cero, buscar alternativas.
    stock_efectivo = info_sucursal.cantidad if info_sucursal.disponible else 0
    alternativas: List[Producto] = []
    if stock_efectivo == 0 or producto.stock == 0:
        alternativas = _buscar_alternativas(db, producto.principio_activo, producto.sku)

    producto_out = ProductoOut.model_validate(producto)
    alternativas_out = [ProductoOut.model_validate(a) for a in alternativas]

    # 6. Completar ficha médica (descripción/origen) con IA si al
    #    catálogo local le falta algún dato -no debería activarse para
    #    este catálogo de ejemplo, que ya viene completo-.
    producto_out = _completar_ficha_medica(producto_out)

    # 7. Enriquecer con fotos reales del catálogo de Farmatodo.
    producto_out, alternativas_out = await _enriquecer_con_fotos_reales(producto_out, alternativas_out)

    return BuscarResponse(
        encontrado=True,
        origen=origen,
        producto=producto_out,
        info_sucursal=info_sucursal,
        principio_activo_detectado=principio_activo_detectado,
        opciones=[],
        alternativas=alternativas_out,
        mensaje=None,
    )
