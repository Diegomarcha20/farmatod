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
   TODOS los candidatos que haya, cada uno con precio en Bs. y en
   CUALQUIER moneda configurada manualmente (con 3% de IGTF aplicado),
   disponibilidad real en la sucursal, categoría, laboratorio/marca y
   foto.
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

import asyncio
import logging
import os
import re
from collections import Counter
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
# 100% manuales: se configuran con la variable de entorno TASAS_CAMBIO,
# formato "USD:246.50,COP%4000" -":" (o "=") significa "cuántos Bs.
# equivalen a 1 unidad de esa moneda" (dividir, la convención estándar
# del dólar); "*" significa "cuántas unidades de esa moneda equivalen
# a 1 Bs." (multiplicar); "%" significa "cuántas unidades de esa
# moneda equivalen a 1 USD" (multiplicar vía dólar, así se suele
# conocer el peso colombiano en la frontera -requiere que "USD"
# también esté configurado-)-. Agregar o quitar una moneda es editar
# esa variable, sin tocar código. Si no está configurada, se usa un
# valor de referencia aproximado -para que la búsqueda de producto
# siga funcionando igual, aunque el precio en divisas no sea exacto-
# en vez de tumbar el endpoint.
_TASAS_FALLBACK = "USD:200,COP%4000"


def _tasas_actuales() -> TasasConfiguracion:
    try:
        return TasasConfiguracion.desde_entorno()
    except TasaInvalidaError as exc:
        logger.warning(
            "Tasas de cambio no configuradas (%s); usando valores de referencia "
            "aproximados. Define TASAS_CAMBIO (ej. \"USD:246.50,COP%%4000\") para "
            "precios reales.",
            exc,
        )
        return TasasConfiguracion.desde_texto(_TASAS_FALLBACK)


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


class PrecioDivisaOut(BaseModel):
    base: float
    igtf_3pct: float
    total_con_igtf: float


class ProductoOut(BaseModel):
    sku: str
    nombre: str
    principio_activo: Optional[str] = None
    categoria: Optional[str] = None
    descripcion: Optional[str] = None
    laboratorio: Optional[str] = None
    pais_origen: Optional[str] = None
    precio_bs: float
    # Una entrada por cada moneda configurada en TASAS_CAMBIO (ej.
    # {"USD": {...}, "COP": {...}}) -no hay un límite fijo de monedas-.
    precios: dict[str, PrecioDivisaOut]
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
    # Resumen único generado por IA para TODO el grupo de opciones (no
    # uno repetido por cada opción) cuando comparten principio activo,
    # ej. "para qué sirve" el Ibuprofeno en general -ver
    # `_resumen_ia_para_opciones`-.
    resumen_ia: Optional[str] = None


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


_PATRON_DOSIS = re.compile(r"(\d+(?:[.,]\d+)?)\s*(mcg|mg|g|ml|l|ui)\b", re.IGNORECASE)
_FACTOR_UNIDAD_MG = {"mcg": 0.001, "mg": 1.0, "g": 1000.0, "ml": 1.0, "l": 1000.0, "ui": 1.0}


def _dosis_normalizada(texto: Optional[str]) -> float:
    """Extrae la primera cantidad+unidad de un texto tipo "Ibuprofeno
    (400 mg)" y la normaliza a una escala comparable, para poder
    ordenar presentaciones de menor a mayor dosis en vez de por texto
    crudo (donde "1000mg" ordenaría antes que "200mg"). Si no reconoce
    nada, devuelve infinito para que quede al final sin romper el
    orden del resto."""
    if not texto:
        return float("inf")
    coincidencia = _PATRON_DOSIS.search(texto)
    if not coincidencia:
        return float("inf")
    valor = float(coincidencia.group(1).replace(",", "."))
    factor = _FACTOR_UNIDAD_MG.get(coincidencia.group(2).lower(), 1.0)
    return valor * factor


def _clave_orden(producto: ProductoOut) -> tuple:
    """Agrupa las opciones por principio activo (o categoría, para
    productos que no son medicamentos) y, dentro de cada grupo, ordena
    por dosis ascendente y luego alfabéticamente por nombre -así
    "Ibuprofeno 200 mg" y "Ibuprofeno 400 mg" de distintos laboratorios
    quedan agrupados y en orden, en vez de mezclados en el orden de
    relevancia crudo de la búsqueda."""
    base = _principio_activo_base(producto.principio_activo) or producto.categoria or producto.nombre
    return (
        (base or "").strip().lower(),
        _dosis_normalizada(producto.principio_activo),
        (producto.nombre or "").strip().lower(),
    )


def _sin_duplicados_y_ordenados(productos: List[ProductoOut]) -> List[ProductoOut]:
    """Quita productos repetidos que a veces trae el catálogo de
    Farmatodo (mismo SKU, o -si faltara el SKU- mismo nombre +
    laboratorio + precio) y ordena el resto agrupando por principio
    activo/dosis en vez de dejar el orden de relevancia crudo."""
    vistos: set[str] = set()
    unicos: List[ProductoOut] = []
    for producto in productos:
        clave = producto.sku or f"{producto.nombre}|{producto.laboratorio}|{producto.precio_bs}"
        if clave in vistos:
            continue
        vistos.add(clave)
        unicos.append(producto)
    return sorted(unicos, key=_clave_orden)


async def _resumen_ia_para_opciones(productos: List[ProductoOut]) -> Optional[str]:
    """Cuando hay varias opciones (distintas marcas/concentraciones)
    para el mismo principio activo, genera UN solo resumen con Gemini
    de "para qué sirve" ese principio activo -en vez de repetir un
    resumen casi idéntico por cada opción, que multiplicaría llamadas
    a la IA sin aportar nada distinto entre una presentación y otra-.
    Si las opciones no comparten un principio activo dominante (p. ej.
    resultados de tipos de producto distintos), no genera nada."""
    bases = [
        base
        for p in productos
        if (base := _principio_activo_base(p.principio_activo))
    ]
    if not bases:
        return None
    base_dominante, conteo = Counter(bases).most_common(1)[0]
    if conteo < len(bases) / 2:
        return None
    # `generar_descripcion` es una llamada SÍNCRONA a la API de Gemini;
    # despachada a un hilo aparte para no bloquear el event loop de
    # FastAPI mientras espera -si no, cualquier otra petición
    # concurrente (de otro empleado, u otra búsqueda del mismo) se
    # quedaría esperando detrás de esta llamada a IA.
    return await asyncio.to_thread(ai_resolver.generar_descripcion, base_dominante, "medicamento")


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
        precios={codigo: PrecioDivisaOut(**valores) for codigo, valores in precios["divisas"].items()},
        en_stock=disponibilidad["en_stock"],
        cantidad_aproximada=disponibilidad["cantidad_aproximada"],
        sucursal=disponibilidad["tienda"],
        imagen_url=candidato.get("imagen_url"),
    )


async def _completar_ficha_medica(producto_out: ProductoOut) -> ProductoOut:
    """Rellena `descripcion` y `pais_origen` con Gemini cuando Farmatodo
    no los trae -que es prácticamente siempre, ya que su catálogo no
    incluye "para qué sirve" ni el país del laboratorio-. Se llama
    únicamente sobre el producto ya confirmado (no por cada opción de
    una lista), para no multiplicar llamadas a la IA. Las llamadas a
    Gemini se despachan a un hilo aparte (`asyncio.to_thread`) porque
    son síncronas y, si no, bloquearían el event loop de FastAPI para
    TODAS las peticiones concurrentes mientras esperan la respuesta."""
    actualizaciones: dict = {}
    pista_para_ia = producto_out.principio_activo or producto_out.categoria or producto_out.nombre

    if not producto_out.descripcion:
        descripcion = await asyncio.to_thread(ai_resolver.generar_descripcion, producto_out.nombre, pista_para_ia)
        if descripcion:
            actualizaciones["descripcion"] = descripcion

    if producto_out.laboratorio and not producto_out.pais_origen:
        origen = await asyncio.to_thread(ai_resolver.identificar_origen_laboratorio, producto_out.laboratorio)
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


async def _respuesta_para_producto_confirmado(
    producto_out: ProductoOut,
    tasas: TasasConfiguracion,
    origen: str,
    principio_activo_detectado: Optional[str],
    fuente: str,
) -> BuscarResponse:
    """Termina de armar la respuesta para un producto YA confirmado (sin
    ambigüedad: o vino de una búsqueda con un solo candidato, o el
    usuario ya eligió uno por SKU exacto en `/producto/{sku}`).
    Compartido entre `/buscar` y `/producto/{sku}` para no duplicar los
    pasos 4 y 5 (completar ficha con IA, buscar alternativas si está
    agotado)."""
    principio_activo_detectado = producto_out.principio_activo or principio_activo_detectado

    # 4. Completar ficha médica (descripción/origen) con IA.
    producto_out = await _completar_ficha_medica(producto_out)

    # 5. Si está agotado, buscar alternativas reales: por el mismo
    #    principio activo si es un medicamento (sin la dosis específica,
    #    para no limitar de más), o por la misma categoría si es
    #    cualquier otro tipo de producto (Farmatodo no vende solo
    #    medicinas).
    alternativas_out: List[ProductoOut] = []
    termino_alternativas = _principio_activo_base(producto_out.principio_activo) or producto_out.categoria
    if not producto_out.en_stock and termino_alternativas:
        resultado_alt = await scraper_service.buscar_catalogo_real(termino_alternativas, tasas)
        alternativas_out = _sin_duplicados_y_ordenados([
            _candidato_a_producto_out(c)
            for c in resultado_alt["candidatos"]
            if c["sku"] != producto_out.sku and c["disponibilidad"]["en_stock"]
        ])

    return BuscarResponse(
        encontrado=True,
        origen=origen,
        producto=producto_out,
        principio_activo_detectado=principio_activo_detectado,
        alternativas=alternativas_out,
        fuente=fuente,
        mensaje=None,
    )


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
        info_ia = await asyncio.to_thread(ai_resolver.extraer_termino_busqueda, consulta)
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

    productos_out = _sin_duplicados_y_ordenados([_candidato_a_producto_out(c) for c in candidatos])

    if len(productos_out) > 1:
        # 3. Varias coincidencias: todas como opciones (sin duplicados,
        #    agrupadas por principio activo/dosis), sin límite ni
        #    adivinar una. Si comparten principio activo, se agrega un
        #    resumen único de IA de "para qué sirve". El usuario elige
        #    una tocándola -la app la resuelve por SKU exacto en
        #    `/producto/{sku}`, NUNCA volviendo a buscar por nombre, para
        #    no arriesgarse a que la relevancia de texto traiga otro
        #    producto distinto-.
        return BuscarResponse(
            encontrado=True,
            origen=origen,
            opciones=productos_out,
            principio_activo_detectado=principio_activo_detectado,
            fuente=resultado["meta"]["fuente"],
            mensaje=f"Se encontraron {len(productos_out)} coincidencias en Farmatodo, elige una.",
            resumen_ia=await _resumen_ia_para_opciones(productos_out),
        )

    # Coincidencia única y confirmada.
    return await _respuesta_para_producto_confirmado(
        productos_out[0], tasas, origen, principio_activo_detectado, resultado["meta"]["fuente"]
    )


@app.get(
    "/producto/{sku}",
    response_model=BuscarResponse,
    tags=["buscar"],
    dependencies=[Depends(verificar_acceso)],
)
async def producto_por_sku(sku: str) -> BuscarResponse:
    """Resuelve EXACTAMENTE un producto por su SKU -pensado para cuando
    el usuario ya eligió una opción entre varias de una búsqueda
    ambigua-. A diferencia de `/buscar`, nunca es ambiguo: o es ese SKU
    exacto, o no se encontró. Reemplaza el patrón anterior de volver a
    buscar por NOMBRE al tocar una opción, que podía abrir un producto
    distinto si la relevancia de texto de Farmatodo traía otra cosa
    primero."""
    tasas = _tasas_actuales()
    candidato = await scraper_service.buscar_por_sku(sku.strip(), tasas)

    if candidato is None:
        return BuscarResponse(
            encontrado=False,
            origen="farmatodo",
            fuente="no_encontrado",
            mensaje=f"No se encontró el producto con SKU {sku} en el catálogo de Farmatodo.",
        )

    producto_out = _candidato_a_producto_out(candidato)
    return await _respuesta_para_producto_confirmado(
        producto_out, tasas, "farmatodo", producto_out.principio_activo, "scraping_real"
    )
