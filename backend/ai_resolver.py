"""
Resolución con IA: cuando la búsqueda local no encuentra una coincidencia
exacta, se le pide a Gemini (Google AI) que interprete la consulta en
lenguaje natural del usuario y devuelva un JSON estructurado con el
principio activo probable, para poder buscar alternativas terapéuticas
en la base local.

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
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

_client: genai.Client | None = None
if GEMINI_API_KEY:
    _client = genai.Client(api_key=GEMINI_API_KEY)

# Evita volver a llamar a Gemini si la misma consulta en lenguaje
# natural ya se resolvió hace menos de 30 minutos: ahorra latencia
# (la llamada a IA es la más lenta de todo el flujo) y consumo de cuota.
CACHE_TTL_SEGUNDOS = int(os.getenv("CACHE_IA_TTL_SEGUNDOS", "1800"))
_cache_ia = TTLCache(ttl_segundos=CACHE_TTL_SEGUNDOS)

SYSTEM_PROMPT = (
    "Eres un asistente farmacéutico. A partir de una consulta en lenguaje "
    "natural de un cliente (por ejemplo, el nombre comercial de un "
    "medicamento, un síntoma, o una descripción vaga), debes identificar el "
    "principio activo farmacológico más probable al que se refiere. "
    "Responde ÚNICAMENTE con un objeto JSON con las siguientes claves:\n"
    '- "principio_activo": nombre genérico del principio activo en español '
    "(ej. Paracetamol, Ibuprofeno, Loratadina). Usa capitalización estándar.\n"
    '- "nombre_comercial_probable": el nombre comercial que el usuario '
    "probablemente quiso escribir, si aplica.\n"
    '- "categoria_terapeutica": categoría terapéutica general.\n'
    '- "confianza": un número entre 0 y 1 indicando qué tan seguro estás.\n'
    "Si no puedes determinar el principio activo, usa null en ese campo."
)

FALLBACK_RESULT = {
    "principio_activo": None,
    "nombre_comercial_probable": None,
    "categoria_terapeutica": None,
    "confianza": 0.0,
    "error": None,
}


def extraer_info_medicamento(consulta: str) -> dict:
    """
    Resuelve el principio activo de una consulta libre con Gemini,
    sirviendo desde caché (TTL configurable, 30 min por defecto) si la
    misma consulta ya se resolvió recientemente. Nunca lanza una
    excepción hacia el llamador.
    """
    clave_cache = (consulta or "").strip().lower()

    if clave_cache:
        cacheado = _cache_ia.obtener(clave_cache)
        if cacheado is not None:
            logger.info("ai_resolver: acierto de caché para %r.", clave_cache)
            return {**cacheado, "desde_cache": True}

    resultado = _extraer_info_medicamento_sin_cache(consulta)

    # Solo se cachean resoluciones exitosas: un fallo transitorio de
    # Gemini no debe "congelar" un error por 30 minutos.
    if clave_cache and not resultado.get("error"):
        _cache_ia.guardar(clave_cache, resultado)

    return {**resultado, "desde_cache": False}


def _extraer_info_medicamento_sin_cache(consulta: str) -> dict:
    """
    Llama a Gemini para extraer el principio activo de una consulta libre.

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

        resultado["principio_activo"] = datos.get("principio_activo")
        resultado["nombre_comercial_probable"] = datos.get("nombre_comercial_probable")
        resultado["categoria_terapeutica"] = datos.get("categoria_terapeutica")
        resultado["confianza"] = datos.get("confianza", 0.0)

    except json.JSONDecodeError as exc:
        resultado["error"] = f"Respuesta de IA no es JSON válido: {exc}"
        logger.error(resultado["error"])
    except Exception as exc:  # noqa: BLE001 - cualquier error de red/API no debe tumbar el endpoint
        resultado["error"] = f"Error consultando Gemini: {exc}"
        logger.error(resultado["error"])

    return resultado


def generar_descripcion(nombre: str, principio_activo: str) -> Optional[str]:
    """Genera con Gemini una descripción breve ("para qué sirve") para
    un producto que no trae una en el catálogo local. Red de seguridad
    para cuando se agreguen productos reales sin ese campo completo;
    para el catálogo de ejemplo no debería activarse -ya viene con
    descripción-. Nunca lanza una excepción: ante cualquier fallo
    devuelve None y el llamador simplemente deja el campo vacío."""
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
                "Eres un asistente farmacéutico. Describe en una o dos frases, "
                "en español claro y neutro, para qué se usa comúnmente este "
                f'medicamento: "{nombre}" (principio activo: {principio_activo}). '
                "No des dosis ni indicaciones médicas personalizadas, solo el uso "
                "general. Responde solo con el texto de la descripción, sin comillas."
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
    laboratorio farmacéutico, cuando el catálogo local no lo trae.
    Misma lógica de red de seguridad que `generar_descripcion`. Nunca
    lanza una excepción."""
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
                f'¿De qué país es el laboratorio farmacéutico "{laboratorio}"? '
                "Responde en una sola frase corta y factual (ej. 'Laboratorio "
                "venezolano.'). Si no lo sabes con certeza, responde exactamente "
                "'Origen no disponible.'"
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
