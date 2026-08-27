"""
Scraper de disponibilidad de sucursal. Consulta (o simula, si la petición
real falla o está bloqueada) la disponibilidad de un producto en la
sucursal "Arbolitos, San Cristóbal", devolviendo cantidad e imagen.

Diseñado para nunca propagar una excepción: cualquier fallo de red,
timeout, bloqueo anti-scraping o cambio de estructura del HTML cae en un
bloque except que produce una respuesta simulada coherente, para que el
endpoint /buscar jamás se caiga por un problema del sitio externo.
"""

import hashlib
import logging
import os

import httpx
from bs4 import BeautifulSoup

from cache import TTLCache

logger = logging.getLogger("scraper")

SUCURSAL_NOMBRE = "Arbolitos, San Cristóbal"

# Evita volver a golpear el sitio de la sucursal si el mismo SKU ya se
# consultó hace menos de 30 minutos: la disponibilidad de un producto
# no cambia segundo a segundo, así que reconsultar en cada búsqueda es
# tráfico (y riesgo de bloqueo) desperdiciado.
CACHE_TTL_SEGUNDOS = int(os.getenv("CACHE_SCRAPER_TTL_SEGUNDOS", "1800"))
_cache_stock = TTLCache(ttl_segundos=CACHE_TTL_SEGUNDOS)

# URL base del sitio de la sucursal a scrapear. Configurable por entorno;
# si no está definida (o el sitio bloquea/falla la petición) se cae al
# modo simulado.
SCRAPER_BASE_URL = os.getenv("SCRAPER_BASE_URL", "").rstrip("/")

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept-Language": "es-VE,es;q=0.9",
}


async def obtener_stock_sucursal(sku: str, nombre: str) -> dict:
    """
    Resuelve disponibilidad en la sucursal Arbolitos, sirviendo desde
    caché (TTL configurable, 30 min por defecto) si el mismo SKU ya se
    consultó recientemente. Si hay que consultar en vivo, intenta el
    scraping real y cae a una respuesta simulada ante cualquier fallo.
    """
    clave_cache = sku.strip().lower()
    cacheado = _cache_stock.obtener(clave_cache)
    if cacheado is not None:
        logger.info("scraper: acierto de caché para SKU %r.", sku)
        return {**cacheado, "desde_cache": True}

    resultado = await _obtener_stock_sucursal_sin_cache(sku, nombre)
    _cache_stock.guardar(clave_cache, resultado)
    return {**resultado, "desde_cache": False}


async def _obtener_stock_sucursal_sin_cache(sku: str, nombre: str) -> dict:
    """
    Intenta obtener disponibilidad real de la sucursal Arbolitos vía
    scraping (httpx + BeautifulSoup). Si algo falla, retorna una
    respuesta simulada determinística basada en el SKU, para que la app
    siempre reciba una respuesta utilizable en un entorno de demo.
    """
    if SCRAPER_BASE_URL:
        try:
            async with httpx.AsyncClient(headers=HEADERS, timeout=6.0) as client:
                url = f"{SCRAPER_BASE_URL}/sucursales/arbolitos-san-cristobal/producto"
                resp = await client.get(url, params={"sku": sku, "q": nombre})
                resp.raise_for_status()

                soup = BeautifulSoup(resp.text, "html.parser")

                stock_el = soup.select_one("[data-stock-cantidad]")
                imagen_el = soup.select_one("[data-producto-imagen] img")
                disponible_el = soup.select_one("[data-disponible]")

                if stock_el is None:
                    raise ValueError(
                        "Estructura HTML inesperada: no se encontró el nodo de stock."
                    )

                cantidad = int(stock_el.get("data-stock-cantidad", "0"))
                disponible = (
                    disponible_el.get("data-disponible", "false").lower() == "true"
                    if disponible_el is not None
                    else cantidad > 0
                )
                imagen_url = imagen_el.get("src") if imagen_el is not None else None

                return {
                    "sucursal": SUCURSAL_NOMBRE,
                    "disponible": disponible,
                    "cantidad": cantidad,
                    "imagen_url": imagen_url,
                    "fuente": "scraping_real",
                }

        except httpx.TimeoutException as exc:
            logger.warning("Timeout consultando sucursal %s: %s", SUCURSAL_NOMBRE, exc)
        except httpx.HTTPStatusError as exc:
            logger.warning(
                "La sucursal respondió con error HTTP (posible bloqueo anti-scraping): %s",
                exc,
            )
        except httpx.RequestError as exc:
            logger.warning("Error de red consultando sucursal %s: %s", SUCURSAL_NOMBRE, exc)
        except (ValueError, AttributeError, TypeError) as exc:
            logger.warning("No se pudo interpretar el HTML de la sucursal: %s", exc)
        except Exception as exc:  # noqa: BLE001 - último resguardo, nunca debe tumbar /buscar
            logger.error("Fallo inesperado en el scraper: %s", exc)

    return _simular_respuesta_sucursal(sku, nombre)


def _simular_respuesta_sucursal(sku: str, nombre: str) -> dict:
    """
    Genera una respuesta simulada pero determinística (misma entrada ->
    misma salida) para un SKU dado, parseada con BeautifulSoup a partir
    de un fragmento HTML de ejemplo que imita la estructura real de la
    página de la sucursal. Se usa cuando no hay SCRAPER_BASE_URL
    configurada o cuando la petición real falla/es bloqueada.
    """
    semilla = int(hashlib.sha256(sku.encode("utf-8")).hexdigest(), 16)
    cantidad = semilla % 12  # 0-11 unidades, reproducible por SKU
    disponible = cantidad > 0

    html_simulado = f"""
    <div class="producto-sucursal" data-sku="{sku}">
        <span class="cantidad">{cantidad}</span>
        <span class="disponible">{"si" if disponible else "no"}</span>
        <img class="foto" src="https://example-farmacia.com/img/sucursal/{sku.lower()}.jpg" />
    </div>
    """
    soup = BeautifulSoup(html_simulado, "html.parser")

    cantidad_el = soup.select_one(".cantidad")
    imagen_el = soup.select_one(".foto")

    return {
        "sucursal": SUCURSAL_NOMBRE,
        "disponible": disponible,
        "cantidad": int(cantidad_el.text) if cantidad_el else 0,
        "imagen_url": imagen_el.get("src") if imagen_el else None,
        "fuente": "simulado",
    }


def estadisticas_cache() -> dict:
    """Expone aciertos/fallos del caché de stock (para /cache/estadisticas)."""
    return _cache_stock.estadisticas()
