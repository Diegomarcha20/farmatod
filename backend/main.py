"""
API principal. Expone /buscar, el endpoint central de la app.

Todo el catálogo sale en tiempo real del catálogo público de Farmatodo
Venezuela (vía scraper_service), para la sucursal "Arbolitos, San
Cristóbal" -no hay un catálogo local propio-. Cubre TODO lo que vende
Farmatodo (medicamentos, cuidado personal, bebé, alimentos, limpieza,
belleza, etc.), no solo medicinas: la meta es que cualquier producto
que exista ahí se pueda encontrar por nombre, sin límite artificial de
resultados.

1. Busca `q` (nombre completo o parcial, código de barras, o consulta
   libre) directamente en el catálogo real de Farmatodo. Devuelve
   TODOS los candidatos que haya, cada uno con precio (Bs./USD con
   IGTF/COP con IGTF), disponibilidad real en la sucursal, categoría,
   laboratorio/marca y foto.
2. Si no hay ninguna coincidencia directa, usa Gemini para interpretar
   la consulta libre (síntoma, necesidad, descripción vaga -de
   cualquier tipo de producto-) y reintenta la búsqueda con el término
   que haya sugerido.
3. Si hay más de un candidato, se devuelven todos como `opciones` para
   que el usuario elija -sin adivinar una-. Si hay exactamente uno, se
   trata como LA respuesta.
4. Con la respuesta ya confirmada: si Farmatodo no trae descripción
   ("para qué es/sirve") o país del laboratorio/marca, se completan
   con Gemini -esos dos datos casi nunca vienen en el catálogo de
   Farmatodo, así que este paso sí se activa de verdad-.
5. Si el producto confirmado está agotado, se busca otra vez en
   Farmatodo por su principio activo (medicamentos) o por su categoría
   (cualquier otro producto) para ofrecer alternativas reales que sí
   tengan stock.

Nota: al venir de Farmatodo, no hay "ubicación en el planograma" (eso
es un dato de la tienda física propia, que Farmatodo no expone para
terceros) -el campo queda presente en el esquema pero vacío-.
"""

import logging
import os
import re
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import ai_resolver
import scraper_service
from currency_converter import TasaInvalidaError, TasasConfiguracion

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


# Tasas de cambio para el motor multidivisa (ver currency_converter.py).
# Si no se configuran TASA_USD_BCV / TASA_COP_USD como variables de
# entorno, se usa un valor de referencia aproximado -para que la
# búsqueda de producto siga funcionando igual, aunque el precio en
# USD/COP no sea exacto- en vez de tumbar el endpoint.
_TASA_USD_BCV_FALLBACK = "200"
_TASA_COP_USD_FALLBACK = "4000"


def _tasas_actuales() -> TasasConfiguracion:
    try:
        return TasasConfiguracion.desde_entorno()
    except TasaInvalidaError as exc:
        logger.warning(
            "Tasas de cambio no configuradas (%s); usando valores de referencia "
            "aproximados. Define TASA_USD_BCV y TASA_COP_USD para precios reales.",
            exc,
        )
        return TasasConfiguracion.crear(
            tasa_usd_bcv=_TASA_USD_BCV_FALLBACK,
            tasa_cop_usd=_TASA_COP_USD_FALLBACK,
        )


app = FastAPI(
    title="API Farmacia - Catálogo real de Farmatodo",
    description=(
        "Backend que busca en tiempo real en TODO el catálogo público de "
        "Farmatodo Venezuela (sucursal Arbolitos, San Cristóbal) -no solo "
        "medicamentos-: precio multidivisa, disponibilidad, laboratorio/"
        "marca y alternativas reales."
    ),
    version="2.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --------------------------------------------------------------------------
# Esquemas de respuesta
# --------------------------------------------------------------------------


class ProductoOut(BaseModel):
    sku: str
    nombre: str
    principio_activo: Optional[str] = None
    categoria: Optional[str] = None
    descripcion: Optional[str] = None
    laboratorio: Optional[str] = None
    pais_origen: Optional[str] = None
    precio_bs: float
    precio_usd: float
    precio_cop: float
    en_stock: bool
    cantidad_aproximada: str
    # Farmatodo no expone el layout físico de una tienda de terceros;
    # queda para cuando el usuario cargue su propia ubicación por SKU.
    ubicacion_planograma: Optional[str] = None
    sucursal: str
    imagen_url: Optional[str] = None


class BuscarResponse(BaseModel):
    encontrado: bool
    origen: str  # "farmatodo" | "ia_gemini"
    producto: Optional[ProductoOut] = None
    principio_activo_detectado: Optional[str] = None
    # Varias coincidencias posibles: el usuario debe elegir una. Cuando
    # no está vacío, `producto` es null.
    opciones: List[ProductoOut] = []
    alternativas: List[ProductoOut] = []
    fuente: Optional[str] = None  # "scraping_real" | "cache" | "error" | "no_encontrado"
    mensaje: Optional[str] = None


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


def _normalizar_texto(texto: Optional[str]) -> Optional[str]:
    """Farmatodo devuelve varios campos en MAYÚSCULAS SIN FORMATO
    ("IBUPROFENO (400 MG)"); se normaliza a algo legible ("Ibuprofeno
    (400 mg)") sin perder la información."""
    if not texto:
        return None
    limpio = texto.strip()
    return limpio.capitalize() if limpio else None


def _principio_activo_base(texto: Optional[str]) -> Optional[str]:
    """Quita la dosis entre paréntesis del final ("Ibuprofeno (400 mg)"
    -> "Ibuprofeno"), para buscar alternativas por el ingrediente en
    general y no solo por esa presentación exacta."""
    if not texto:
        return None
    sin_dosis = re.sub(r"\s*\([^)]*\)\s*$", "", texto).strip()
    return sin_dosis or texto


def _candidato_a_producto_out(candidato: dict) -> ProductoOut:
    disponibilidad = candidato["disponibilidad"]
    precios = candidato["precios"]
    return ProductoOut(
        sku=candidato["sku"] or "",
        nombre=candidato.get("nombre_comercial") or candidato["sku"] or "Producto sin nombre",
        principio_activo=_normalizar_texto(candidato.get("principio_activo")),
        categoria=_normalizar_texto(candidato.get("categoria")),
        laboratorio=candidato.get("laboratorio"),
        precio_bs=precios["bs"],
        precio_usd=precios["usd"]["total_con_igtf"],
        precio_cop=precios["cop"]["total_con_igtf"],
        en_stock=disponibilidad["en_stock"],
        cantidad_aproximada=disponibilidad["cantidad_aproximada"],
        sucursal=disponibilidad["tienda"],
        imagen_url=candidato.get("imagen_url"),
    )


def _completar_ficha_medica(producto_out: ProductoOut) -> ProductoOut:
    """Rellena `descripcion` y `pais_origen` con Gemini cuando Farmatodo
    no los trae -que es prácticamente siempre, ya que su catálogo no
    incluye "para qué sirve" ni el país del laboratorio-. Se llama
    únicamente sobre el producto ya confirmado (no por cada opción de
    una lista), para no multiplicar llamadas a la IA."""
    actualizaciones: dict = {}
    pista_para_ia = producto_out.principio_activo or producto_out.categoria or producto_out.nombre

    if not producto_out.descripcion:
        descripcion = ai_resolver.generar_descripcion(producto_out.nombre, pista_para_ia)
        if descripcion:
            actualizaciones["descripcion"] = descripcion

    if producto_out.laboratorio and not producto_out.pais_origen:
        origen = ai_resolver.identificar_origen_laboratorio(producto_out.laboratorio)
        if origen:
            actualizaciones["pais_origen"] = origen

    return producto_out.model_copy(update=actualizaciones) if actualizaciones else producto_out


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------


@app.get("/", tags=["salud"])
def salud() -> dict:
    return {"status": "ok", "servicio": "API Farmacia"}


@app.get("/cache/estadisticas", tags=["salud"], dependencies=[Depends(verificar_acceso)])
def estadisticas_cache() -> dict:
    """Aciertos/fallos de los cachés de IA y del catálogo de Farmatodo
    -útil para confirmar en producción que el caché de 30 min realmente
    está evitando llamadas repetidas a Gemini y a Farmatodo-."""
    return {
        "ia": ai_resolver.estadisticas_cache(),
        "farmatodo": scraper_service.estadisticas_cache(),
    }


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
        description="Nombre completo o parcial, código de barras, o síntoma/descripción libre",
    ),
) -> BuscarResponse:
    consulta = q.strip()
    tasas = _tasas_actuales()

    # 1. Buscar directo en el catálogo real de Farmatodo.
    resultado = await scraper_service.buscar_catalogo_real(consulta, tasas)
    candidatos = resultado["candidatos"]
    origen = "farmatodo"
    principio_activo_detectado: Optional[str] = None

    if not candidatos:
        # 2. Nada directo -> resolver con Gemini a partir de la consulta
        #    libre (síntoma, necesidad, descripción vaga -de cualquier
        #    tipo de producto, no solo medicamentos-) y reintentar en
        #    Farmatodo con el término que haya sugerido.
        origen = "ia_gemini"
        info_ia = ai_resolver.extraer_termino_busqueda(consulta)
        principio_activo_detectado = info_ia.get("termino_sugerido")

        if info_ia.get("error"):
            logger.warning("ai_resolver: %s", info_ia["error"])

        if principio_activo_detectado:
            resultado = await scraper_service.buscar_catalogo_real(principio_activo_detectado, tasas)
            candidatos = resultado["candidatos"]

    if not candidatos:
        return BuscarResponse(
            encontrado=False,
            origen=origen,
            principio_activo_detectado=principio_activo_detectado,
            fuente=resultado["meta"]["fuente"],
            mensaje=resultado["meta"].get("advertencia")
            or "No se encontró el producto en el catálogo de Farmatodo.",
        )

    productos_out = [_candidato_a_producto_out(c) for c in candidatos]

    if len(productos_out) > 1:
        # 3. Varias coincidencias: todas como opciones, sin límite ni
        #    adivinar una.
        return BuscarResponse(
            encontrado=True,
            origen=origen,
            opciones=productos_out,
            principio_activo_detectado=principio_activo_detectado,
            fuente=resultado["meta"]["fuente"],
            mensaje=f"Se encontraron {len(productos_out)} coincidencias en Farmatodo, elige una.",
        )

    # Coincidencia única y confirmada.
    producto_out = productos_out[0]
    principio_activo_detectado = producto_out.principio_activo or principio_activo_detectado

    # 4. Completar ficha médica (descripción/origen) con IA.
    producto_out = _completar_ficha_medica(producto_out)

    # 5. Si está agotado, buscar alternativas reales: por el mismo
    #    principio activo si es un medicamento (sin la dosis específica,
    #    para no limitar de más), o por la misma categoría si es
    #    cualquier otro tipo de producto (Farmatodo no vende solo
    #    medicinas).
    alternativas_out: List[ProductoOut] = []
    termino_alternativas = _principio_activo_base(producto_out.principio_activo) or producto_out.categoria
    if not producto_out.en_stock and termino_alternativas:
        resultado_alt = await scraper_service.buscar_catalogo_real(termino_alternativas, tasas)
        alternativas_out = [
            _candidato_a_producto_out(c)
            for c in resultado_alt["candidatos"]
            if c["sku"] != producto_out.sku and c["disponibilidad"]["en_stock"]
        ]

    return BuscarResponse(
        encontrado=True,
        origen=origen,
        producto=producto_out,
        principio_activo_detectado=principio_activo_detectado,
        alternativas=alternativas_out,
        fuente=resultado["meta"]["fuente"],
        mensaje=None,
    )
