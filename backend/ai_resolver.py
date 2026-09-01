"""
Resolución con IA: cuando la búsqueda directa en el catálogo real de
Farmatodo no encuentra ninguna coincidencia, se le pide a Gemini
(Google AI) que interprete la consulta en lenguaje natural del cliente
-un síntoma, una necesidad, una descripción vaga, de CUALQUIER tipo de
producto (Farmatodo vende medicamentos, cuidado personal, bebé,
alimentos, limpieza, belleza, etc., no solo medicina)- y devuelva un
término de búsqueda mejor, para reintentar en el catálogo real.

Se eligió Gemini sobre OpenAI porque su nivel gratuito (Google AI
Studio) no exige tarjeta de crédito para empezar a usarlo, lo cual es
más práctico para una herramienta de un solo local.
"""

import json
import logging
import os
from typing import Optional

from dotenv import load_dotenv
from google import genai
from google.genai import types

from cache import TTLCache

load_dotenv()

logger = logging.getLogger("ai_resolver")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# "gemini-3.6-flash" (usado antes) tiene un tope de solo 20 peticiones
# POR DÍA en el nivel gratuito -confirmado en vivo, se agota casi de
# inmediato con uso real de la app (cada producto que se abre pide una
# descripción a la IA)-. Las variantes "flash-lite" están pensadas
# para volumen alto en el nivel gratuito; probado en vivo, 10/10
# peticiones seguidas sin toparse con ningún límite. "-latest" (en vez
# de fijar una versión) para no volver a toparnos con un modelo
# descontinuado ("ya no disponible para cuentas nuevas") cuando Google
# libere la siguiente versión.
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest")

_client: genai.Client | None = None
if GEMINI_API_KEY:
    # Timeout explícito: sin esto, una llamada a Gemini que se cuelga
    # (red lenta, el propio servicio de Google degradado) podía
    # retener la respuesta de /buscar indefinidamente. Acotado a 12s
    # -generoso para una respuesta normal, pero sin dejar la búsqueda
    # colgada por un dato de IA que de todas formas es opcional-.
    _client = genai.Client(api_key=GEMINI_API_KEY, http_options=types.HttpOptions(timeout=12000))

# Evita volver a llamar a Gemini si la misma consulta en lenguaje
# natural ya se resolvió hace menos de 30 minutos: ahorra latencia
# (la llamada a IA es la más lenta de todo el flujo) y consumo de cuota.
CACHE_TTL_SEGUNDOS = int(os.getenv("CACHE_IA_TTL_SEGUNDOS", "1800"))
_cache_ia = TTLCache(ttl_segundos=CACHE_TTL_SEGUNDOS)

SYSTEM_PROMPT = (
    "Eres un asistente de búsqueda para Farmatodo, una tienda que vende de "
    "todo: medicamentos, cuidado personal, higiene, bebé, alimentos y "
    "bebidas, limpieza del hogar, belleza, etc. -no es una farmacia que "
    "solo vende medicinas-. A partir de una consulta en lenguaje natural de "
    "un cliente (un síntoma, una necesidad, un nombre comercial mal "
    "escrito, o una descripción vaga de CUALQUIER producto que Farmatodo "
    "podría vender), sugiere el mejor término para buscar en el catálogo. "
    "Responde ÚNICAMENTE con un objeto JSON con las siguientes claves:\n"
    '- "termino_sugerido": el término más efectivo para buscar el producto '
    "en el catálogo -si es un tema de salud, el principio activo "
    "farmacológico (ej. Paracetamol, Ibuprofeno); si es cualquier otro tipo "
    "de producto, el nombre genérico o tipo de producto (ej. Champú "
    "anticaspa, Pañales talla G, Papel higiénico). Usa capitalización "
    "estándar.\n"
    '- "nombre_comercial_probable": el nombre comercial que el usuario '
    "probablemente quiso escribir, si aplica.\n"
    '- "categoria_probable": categoría general del producto (ej. '
    '"Analgésico", "Cuidado del cabello", "Higiene del bebé").\n'
    '- "confianza": un número entre 0 y 1 indicando qué tan seguro estás.\n'
    "Si no puedes determinar nada razonable, usa null en esos campos."
)

FALLBACK_RESULT = {
    "termino_sugerido": None,
    "nombre_comercial_probable": None,
    "categoria_probable": None,
    "confianza": 0.0,
    "error": None,
}


def extraer_termino_busqueda(consulta: str) -> dict:
    """
    Resuelve el mejor término de búsqueda para una consulta libre (de
    cualquier tipo de producto Farmatodo, no solo medicamentos) con
    Gemini, sirviendo desde caché (TTL configurable, 30 min por
    defecto) si la misma consulta ya se resolvió recientemente. Nunca
    lanza una excepción hacia el llamador.
    """
    clave_cache = (consulta or "").strip().lower()

    if clave_cache:
        cacheado = _cache_ia.obtener(clave_cache)
        if cacheado is not None:
            logger.info("ai_resolver: acierto de caché para %r.", clave_cache)
            return {**cacheado, "desde_cache": True}

    resultado = _extraer_termino_busqueda_sin_cache(consulta)

    # Solo se cachean resoluciones exitosas: un fallo transitorio de
    # Gemini no debe "congelar" un error por 30 minutos.
    if clave_cache and not resultado.get("error"):
        _cache_ia.guardar(clave_cache, resultado)

    return {**resultado, "desde_cache": False}


def _extraer_termino_busqueda_sin_cache(consulta: str) -> dict:
    """
    Llama a Gemini para sugerir un término de búsqueda a partir de una
    consulta libre.

    Nunca lanza una excepción hacia el llamador: ante cualquier fallo
    (sin API key, timeout, respuesta no parseable, error de la API, etc.)
    devuelve FALLBACK_RESULT con el detalle del error en la clave "error",
    para que el endpoint /buscar pueda seguir funcionando sin IA.
    """
    resultado = dict(FALLBACK_RESULT)

    if not _client:
        resultado["error"] = "GEMINI_API_KEY no configurada en el entorno."
        logger.warning(resultado["error"])
        return resultado

    consulta = (consulta or "").strip()
    if not consulta:
        resultado["error"] = "Consulta vacía."
        return resultado

    try:
        respuesta = _client.models.generate_content(
            model=GEMINI_MODEL,
            contents=f"{SYSTEM_PROMPT}\n\nConsulta del cliente: {consulta}",
            config=types.GenerateContentConfig(
                temperature=0,
                response_mime_type="application/json",
            ),
        )

        contenido = respuesta.text or "{}"
        datos = json.loads(contenido)

        resultado["termino_sugerido"] = datos.get("termino_sugerido")
        resultado["nombre_comercial_probable"] = datos.get("nombre_comercial_probable")
        resultado["categoria_probable"] = datos.get("categoria_probable")
        resultado["confianza"] = datos.get("confianza", 0.0)

    except json.JSONDecodeError as exc:
        resultado["error"] = f"Respuesta de IA no es JSON válido: {exc}"
        logger.error(resultado["error"])
    except Exception as exc:  # noqa: BLE001 - cualquier error de red/API no debe tumbar el endpoint
        resultado["error"] = f"Error consultando Gemini: {exc}"
        logger.error(resultado["error"])

    return resultado


def generar_descripcion(nombre: str, pista: str) -> Optional[str]:
    """Genera con Gemini una descripción breve ("para qué es/sirve")
    para un producto que Farmatodo no trae -su catálogo casi nunca
    incluye esto, así que este paso se activa de verdad para cualquier
    tipo de producto, no solo medicamentos-. `pista` es el mejor dato
    de contexto disponible (principio activo si es un medicamento,
    categoría si es cualquier otro producto). Nunca lanza una
    excepción: ante cualquier fallo devuelve None y el llamador
    simplemente deja el campo vacío."""
    clave_cache = f"descripcion::{nombre.strip().lower()}"
    cacheado = _cache_ia.obtener(clave_cache)
    if cacheado is not None:
        return cacheado or None

    if not _client:
        return None

    try:
        respuesta = _client.models.generate_content(
            model=GEMINI_MODEL,
            contents=(
                "Eres un asistente de una tienda tipo farmacia que vende de "
                "todo (medicamentos, cuidado personal, bebé, alimentos, "
                "limpieza, belleza, etc.). Describe en una o dos frases, en "
                f'español claro y neutro, qué es o para qué sirve: "{nombre}" '
                f"(contexto: {pista}). Si es un medicamento, no des dosis ni "
                "indicaciones médicas personalizadas, solo el uso general. "
                "Responde solo con el texto de la descripción, sin comillas."
            ),
            config=types.GenerateContentConfig(temperature=0.2),
        )
        texto = (respuesta.text or "").strip()
        _cache_ia.guardar(clave_cache, texto)
        return texto or None
    except Exception as exc:  # noqa: BLE001 - enriquecimiento best-effort, nunca debe romper /buscar
        logger.warning("No se pudo generar descripción con Gemini: %s", exc)
        return None


def identificar_origen_laboratorio(laboratorio: str) -> Optional[str]:
    """Genera con Gemini una frase corta sobre el país/origen de un
    laboratorio o marca/fabricante (no todo lo que vende Farmatodo es
    de un laboratorio farmacéutico -puede ser una marca de cuidado
    personal, alimentos, etc.-), cuando el catálogo no lo trae. Misma
    lógica de red de seguridad que `generar_descripcion`. Nunca lanza
    una excepción."""
    clave_cache = f"origen::{laboratorio.strip().lower()}"
    cacheado = _cache_ia.obtener(clave_cache)
    if cacheado is not None:
        return cacheado or None

    if not _client:
        return None

    try:
        respuesta = _client.models.generate_content(
            model=GEMINI_MODEL,
            contents=(
                f'¿De qué país es el laboratorio, marca o fabricante "{laboratorio}"? '
                "Responde en una sola frase corta y factual (ej. 'Marca "
                "venezolana.' o 'Laboratorio venezolano.'). Si no lo sabes con "
                "certeza, responde exactamente 'Origen no disponible.'"
            ),
            config=types.GenerateContentConfig(temperature=0),
        )
        texto = (respuesta.text or "").strip()
        _cache_ia.guardar(clave_cache, texto)
        return texto or None
    except Exception as exc:  # noqa: BLE001 - enriquecimiento best-effort, nunca debe romper /buscar
        logger.warning("No se pudo identificar el origen del laboratorio con Gemini: %s", exc)
        return None


def estadisticas_cache() -> dict:
    """Expone aciertos/fallos del caché de IA (para /cache/estadisticas)."""
    return _cache_ia.estadisticas()
