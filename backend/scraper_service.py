"""
scraper_service.py

Cliente asíncrono para consultar en tiempo real el catálogo público de
Farmatodo Venezuela (farmatodo.com.ve) y resolver disponibilidad y
precio para una sucursal específica -por defecto "Los Arbolitos", San
Cristóbal (Táchira)-.

--------------------------------------------------------------------
Arquitectura real descubierta (inspección de tráfico, 2026-08-25)
--------------------------------------------------------------------
Se navegó farmatodo.com.ve como visitante anónimo (sin iniciar sesión)
y se inspeccionó el tráfico de red generado por su propio frontend
Angular:

1. Búsqueda de producto: el sitio consulta un índice de Algolia a
   través de un proxy propio, `POST /1/indexes/*/queries` en
   `api-search.farmatodo.com`, usando una API key de Algolia de tipo
   "search-only" (por diseño de Algolia, pensada para ir embebida en
   clientes públicos, a diferencia de una admin key) junto con los
   encabezados `x-algolia-application-id` / `x-algolia-api-key` y un
   `x-custom-city` que fija el contexto regional de precios/ofertas.
   Cada visitante genera sus propios identificadores de sesión
   (`x-ts-opaqueuserid`, `userToken`) de forma aleatoria en el propio
   navegador -no existe credencial de usuario ni token de servidor
   involucrado-.
2. Disponibilidad por tienda: cada resultado de Algolia trae un campo
   `stores_with_stock` con los IDs numéricos de todas las tiendas a
   nivel nacional que reportan stock del producto. La tienda
   "Los Arbolitos, San Cristóbal" corresponde al ID de tienda 599
   (código de ciudad "SNCR"), confirmado contra el localizador público
   de tiendas (`api-transactional.farmatodo.com/route/r/VE/v1/stores/nearby`).
3. Precio y oferta por ciudad: cada resultado también trae
   `fullPriceByCity` / `offerPriceByCity`, listas con el precio base y
   la oferta vigente (si la hay) para cada código de ciudad -el precio
   efectivo SÍ puede variar por ciudad-; se usa el código "SNCR" para
   obtener el precio que vería un cliente de San Cristóbal.
4. Ficha de producto: como fuente secundaria de validación se usa el
   bloque `<script type="application/ld+json">` (schema.org/Product)
   que Farmatodo expone ya renderizado en el HTML de cada página de
   producto (SSR) -metadato estándar pensado para ser leído por
   máquinas (buscadores, agregadores)-.

Este mapeo refleja el estado del sitio en la fecha indicada. Farmatodo
puede rotar claves, renombrar campos o bloquear tráfico automatizado
en cualquier momento sin aviso -por eso cada llamada de red está
aislada en su propio try/except y, ante cualquier fallo, el servicio
degrada a caché o a una respuesta simulada en lugar de propagar la
excepción y tumbar al servidor que lo use.

Aviso de uso: este cliente consulta el sitio de un tercero. Antes de
usarlo en producción o a volumen, confirma que tienes autorización
para automatizar estas consultas conforme a los Términos de Uso de
Farmatodo, y respeta límites de frecuencia razonables.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import time
import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Optional
from urllib.parse import urlencode

import httpx
from bs4 import BeautifulSoup

from cache import TTLCache
from currency_converter import TasasConfiguracion, calcular_precios

logger = logging.getLogger("scraper_service")

ALGOLIA_SEARCH_URL = os.getenv(
    "FARMATODO_ALGOLIA_SEARCH_URL", "https://api-search.farmatodo.com/1/indexes/*/queries"
)
ALGOLIA_APP_ID = os.getenv("FARMATODO_ALGOLIA_APP_ID", "VCOJEYD2PO")
ALGOLIA_SEARCH_KEY = os.getenv("FARMATODO_ALGOLIA_SEARCH_KEY", "869a91e98550dd668b8b1dc04bca9011")
ALGOLIA_INDEX = os.getenv("FARMATODO_ALGOLIA_INDEX", "products-venezuela")
SITIO_BASE_URL = os.getenv("FARMATODO_BASE_URL", "https://www.farmatodo.com.ve")

# Reintentos: 403/429 pueden ser bloqueos temporales de WAF o límites
# de tasa transitorios; 5xx son errores del servidor. Se reintenta un
# número acotado de veces con backoff exponencial + jitter; nunca en
# bucle indefinido.
CODIGOS_REINTENTABLES = {403, 429, 500, 502, 503, 504}

USER_AGENTS_REALES = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.4 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0.0.0 Safari/537.36",
]


def _user_agent_aleatorio() -> str:
    return random.choice(USER_AGENTS_REALES)


class ScraperError(Exception):
    """Error de red/parseo al consultar Farmatodo. Se captura siempre
    internamente; se expone solo para pruebas unitarias específicas."""


@dataclass(frozen=True)
class TiendaObjetivo:
    """Sucursal cuyo contexto de inventario/precio se fuerza en cada
    consulta. Configurable para reutilizar el cliente con otra tienda."""

    nombre_visible: str = "Arbolitos, San Cristóbal"
    store_id: int = 599
    city_id: str = "SNCR"


class _CachePorTermino:
    """Caché en memoria, con expiración, del último resultado exitoso
    por término de búsqueda. Es el "dato en caché" que el spec pide
    devolver cuando el scraping en vivo falla."""

    def __init__(self, ttl_segundos: int = 1800) -> None:
        self._ttl = ttl_segundos
        self._datos: dict[str, tuple[float, dict[str, Any]]] = {}

    def obtener(self, clave: str) -> Optional[dict[str, Any]]:
        entrada = self._datos.get(clave)
        if entrada is None:
            return None
        guardado_en, valor = entrada
        if time.monotonic() - guardado_en > self._ttl:
            return None
        return valor

    def guardar(self, clave: str, valor: dict[str, Any]) -> None:
        self._datos[clave] = (time.monotonic(), valor)


class FarmatodoScraper:
    def __init__(
        self,
        tienda: TiendaObjetivo = TiendaObjetivo(),
        timeout_segundos: float = 10.0,
        max_reintentos: int = 3,
        backoff_base_segundos: float = 0.6,
        cache_ttl_segundos: int = 1800,
    ) -> None:
        self._tienda = tienda
        self._timeout = timeout_segundos
        self._max_reintentos = max_reintentos
        self._backoff_base = backoff_base_segundos
        self._cache = _CachePorTermino(ttl_segundos=cache_ttl_segundos)
        self._client: Optional[httpx.AsyncClient] = None

    async def __aenter__(self) -> "FarmatodoScraper":
        self._client = httpx.AsyncClient(timeout=httpx.Timeout(self._timeout))
        return self

    async def __aexit__(self, *_exc_info: Any) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    def _cliente(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError(
                "FarmatodoScraper debe usarse como context manager: "
                "'async with FarmatodoScraper() as scraper:'."
            )
        return self._client

    async def _solicitar_con_reintentos(
        self, metodo: str, url: str, **kwargs: Any
    ) -> httpx.Response:
        cliente = self._cliente()
        ultimo_error: Optional[BaseException] = None

        for intento in range(1, self._max_reintentos + 1):
            kwargs.setdefault("headers", {})
            kwargs["headers"].setdefault("User-Agent", _user_agent_aleatorio())
            try:
                respuesta = await cliente.request(metodo, url, **kwargs)
            except (httpx.TimeoutException, httpx.ConnectError, httpx.ReadError) as exc:
                ultimo_error = exc
                logger.warning(
                    "Intento %d/%d: fallo de red hacia %s: %s",
                    intento, self._max_reintentos, url, exc,
                )
            else:
                if respuesta.status_code < 400:
                    return respuesta

                if respuesta.status_code not in CODIGOS_REINTENTABLES:
                    respuesta.raise_for_status()

                ultimo_error = httpx.HTTPStatusError(
                    f"Respuesta {respuesta.status_code} de {url}",
                    request=respuesta.request,
                    response=respuesta,
                )
                logger.warning(
                    "Intento %d/%d: %s respondió %d (reintentable).",
                    intento, self._max_reintentos, url, respuesta.status_code,
                )

                espera = self._calcular_espera(intento, respuesta)
                if intento < self._max_reintentos:
                    await asyncio.sleep(espera)
                continue

            if intento < self._max_reintentos:
                await asyncio.sleep(self._calcular_espera(intento, None))

        raise ScraperError(f"Agotados los reintentos hacia {url}: {ultimo_error}") from ultimo_error

    def _calcular_espera(self, intento: int, respuesta: Optional[httpx.Response]) -> float:
        if respuesta is not None:
            retry_after = respuesta.headers.get("Retry-After")
            if retry_after is not None:
                try:
                    return min(float(retry_after), 8.0)
                except ValueError:
                    pass
        base = self._backoff_base * (2 ** (intento - 1))
        jitter = random.uniform(0, self._backoff_base)
        return min(base + jitter, 8.0)

    def _headers_algolia(self) -> dict[str, str]:
        return {
            "Content-Type": "application/json",
            "x-algolia-api-key": ALGOLIA_SEARCH_KEY,
            "x-algolia-application-id": ALGOLIA_APP_ID,
            "x-custom-city": self._tienda.city_id,
            "x-country": "VE",
            "x-anonymous": "true",
            "x-ts-opaqueuserid": uuid.uuid4().hex,
            "Accept-Language": "es-VE,es;q=0.9",
        }

    def _cuerpo_algolia(self, termino: str) -> dict[str, Any]:
        params = urlencode(
            {
                "hitsPerPage": 5,
                "page": 0,
                "filters": "outofstore:false ",
                "clickAnalytics": "true",
                "userToken": f"anonymous-{uuid.uuid4()}",
            }
        )
        return {
            "requests": [
                {
                    "indexName": ALGOLIA_INDEX,
                    "query": termino,
                    "params": params,
                }
            ]
        }

    async def _buscar_en_algolia(self, termino: str) -> Optional[dict[str, Any]]:
        respuesta = await self._solicitar_con_reintentos(
            "POST",
            ALGOLIA_SEARCH_URL,
            headers=self._headers_algolia(),
            json=self._cuerpo_algolia(termino),
        )
        cuerpo = respuesta.json()
        resultados = cuerpo.get("results") or []
        if not resultados:
            return None
        hits = resultados[0].get("hits") or []
        if not hits:
            return None
        return hits[0]

    async def _ficha_ssr(self, url_slug: str) -> Optional[dict[str, Any]]:
        """Segunda fuente, opcional y no bloqueante: intenta leer el
        JSON-LD (schema.org/Product) de la página de producto
        renderizada en servidor, para obtener un nombre comercial
        limpio. Si falla por cualquier motivo, se ignora sin afectar
        el resultado principal."""
        try:
            respuesta = await self._solicitar_con_reintentos(
                "GET",
                f"{SITIO_BASE_URL}/producto/{url_slug}",
                headers={"Accept": "text/html"},
            )
            soup = BeautifulSoup(respuesta.text, "html.parser")
            bloque = soup.find("script", attrs={"type": "application/ld+json"})
            if bloque is None or not bloque.string:
                return None
            data = json.loads(bloque.string)
            return data if isinstance(data, dict) else None
        except Exception as exc:  # noqa: BLE001 - fuente secundaria, nunca debe romper la principal
            logger.info("No se pudo enriquecer con la ficha SSR de %s: %s", url_slug, exc)
            return None

    def _precio_bs_para_tienda(self, hit: dict[str, Any]) -> Decimal:
        city_id = self._tienda.city_id

        for oferta in hit.get("offerPriceByCity") or []:
            if oferta.get("cityCode") == city_id and oferta.get("offerPrice"):
                return Decimal(str(oferta["offerPrice"]))

        for precio in hit.get("fullPriceByCity") or []:
            if precio.get("cityCode") == city_id and precio.get("fullPrice") is not None:
                return Decimal(str(precio["fullPrice"]))

        return Decimal(str(hit.get("fullPrice", 0)))

    def _en_stock_para_tienda(self, hit: dict[str, Any]) -> bool:
        return self._tienda.store_id in (hit.get("stores_with_stock") or [])

    def _cantidad_aproximada(self, hit: dict[str, Any], en_stock: bool) -> str:
        if not en_stock:
            return "Agotado en esta tienda"
        if hit.get("lowStock"):
            return hit.get("lowStockLabel") or "Pocas unidades"
        return "Disponible"

    def _nombre_desde_slug(self, url_slug: str) -> str:
        partes = url_slug.split("-")
        if partes and partes[0].isdigit():
            partes = partes[1:]
        return " ".join(partes).strip().capitalize() or url_slug

    async def _construir_resultado(self, hit: dict[str, Any], tasas: TasasConfiguracion) -> dict[str, Any]:
        sku = str(hit.get("item") or hit.get("objectID") or hit.get("sku_searchable") or "")
        url_slug = hit.get("url") or ""
        en_stock = self._en_stock_para_tienda(hit)
        precio_bs = self._precio_bs_para_tienda(hit)

        nombre_comercial = self._nombre_desde_slug(url_slug) if url_slug else sku
        imagen_url = hit.get("mediaImageUrl") or next(iter(hit.get("listUrlImages") or []), None)

        ficha = await self._ficha_ssr(url_slug) if url_slug else None
        if ficha:
            oferta = ficha.get("offers") or {}
            nombre_comercial = (ficha.get("name") or nombre_comercial).strip()
            imagen_url = ficha.get("image") or imagen_url
            if not precio_bs and oferta.get("price"):
                precio_bs = Decimal(str(oferta["price"]))

        return {
            "sku": sku,
            "nombre_comercial": nombre_comercial,
            "disponibilidad": {
                "tienda": self._tienda.nombre_visible,
                "en_stock": en_stock,
                "cantidad_aproximada": self._cantidad_aproximada(hit, en_stock),
            },
            "precios": calcular_precios(precio_bs, tasas),
            "imagen_url": imagen_url,
            "meta": {"fuente": "scraping_real", "advertencia": None},
        }

    def _respuesta_no_encontrado(self, termino: str) -> dict[str, Any]:
        return {
            "sku": None,
            "nombre_comercial": None,
            "disponibilidad": {
                "tienda": self._tienda.nombre_visible,
                "en_stock": False,
                "cantidad_aproximada": "No encontrado",
            },
            "precios": None,
            "imagen_url": None,
            "meta": {
                "fuente": "no_encontrado",
                "advertencia": f"Sin coincidencias para '{termino}' en el catálogo de Farmatodo.",
            },
        }

    def _respuesta_simulada(self, termino: str, tasas: TasasConfiguracion, motivo: str) -> dict[str, Any]:
        """Fallback determinístico (misma entrada -> misma salida) para
        cuando el scraping en vivo falla y no hay nada en caché. Evita
        que el servidor que consuma este cliente se caiga."""
        semilla = abs(hash(termino.strip().lower())) % 900000 + 100000
        precio_bs = Decimal(semilla % 5000 + 50)
        en_stock = semilla % 3 != 0

        return {
            "sku": str(semilla),
            "nombre_comercial": termino.strip().title(),
            "disponibilidad": {
                "tienda": self._tienda.nombre_visible,
                "en_stock": en_stock,
                "cantidad_aproximada": "Disponible" if en_stock else "Agotado en esta tienda",
            },
            "precios": calcular_precios(precio_bs, tasas),
            "imagen_url": None,
            "meta": {
                "fuente": "simulado",
                "advertencia": (
                    "No se pudo consultar Farmatodo en tiempo real "
                    f"({motivo}); se devuelve un estimado simulado de referencia."
                ),
            },
        }

    async def buscar_producto(self, termino: str, tasas: Optional[TasasConfiguracion] = None) -> dict[str, Any]:
        """Punto de entrada principal: busca `termino` en Farmatodo,
        resuelve disponibilidad y precio para la tienda configurada, y
        devuelve el payload ya con la conversión multidivisa aplicada.
        Nunca lanza una excepción hacia el llamador."""
        tasas = tasas or TasasConfiguracion.desde_entorno()
        clave_cache = termino.strip().lower()

        try:
            hit = await self._buscar_en_algolia(termino)
        except Exception as exc:  # noqa: BLE001 - cualquier fallo de red/API cae a caché o simulado
            logger.warning("Fallo consultando Farmatodo en vivo para %r: %s", termino, exc)
            cacheado = self._cache.obtener(clave_cache)
            if cacheado is not None:
                return {
                    **cacheado,
                    "meta": {
                        "fuente": "cache",
                        "advertencia": f"Farmatodo no respondió ({exc}); se devuelve el último dato en caché.",
                    },
                }
            return self._respuesta_simulada(termino, tasas, motivo=str(exc))

        if hit is None:
            return self._respuesta_no_encontrado(termino)

        try:
            resultado = await self._construir_resultado(hit, tasas)
        except Exception as exc:  # noqa: BLE001 - error de parseo/estructura del DOM/JSON
            logger.warning("Fallo interpretando la respuesta de Farmatodo para %r: %s", termino, exc)
            cacheado = self._cache.obtener(clave_cache)
            if cacheado is not None:
                return {
                    **cacheado,
                    "meta": {
                        "fuente": "cache",
                        "advertencia": f"Estructura de datos inesperada ({exc}); se devuelve el último dato en caché.",
                    },
                }
            return self._respuesta_simulada(termino, tasas, motivo=str(exc))

        self._cache.guardar(clave_cache, resultado)
        return resultado


# --------------------------------------------------------------------------
# Enriquecimiento de fotos para OTROS catálogos (p. ej. el demo local de la
# farmacia): busca `termino` en el catálogo real de Farmatodo y devuelve
# solo una foto de referencia, sin acoplar stock/precio -esos siguen
# viniendo de la base local-. Pensado para que CUALQUIER búsqueda (por
# nombre, SKU, código de barras o principio activo resuelto por IA) pueda
# mostrar una foto real en vez del placeholder genérico.
# --------------------------------------------------------------------------

# Sentinela para cachear explícitamente "se consultó y no hay foto", y así
# distinguirlo de "todavía no se consultó" (que también se lee como None).
_SIN_IMAGEN = ""

CACHE_IMAGEN_TTL_SEGUNDOS = int(os.getenv("CACHE_IMAGEN_TTL_SEGUNDOS", "1800"))
_cache_imagenes = TTLCache(ttl_segundos=CACHE_IMAGEN_TTL_SEGUNDOS)


async def obtener_imagen_producto(termino: str) -> Optional[str]:
    """Devuelve una URL de foto real del catálogo de Farmatodo para
    `termino` (nombre o principio activo), o None si no se encuentra o
    la consulta falla por cualquier motivo. Nunca lanza una excepción:
    es un enriquecimiento visual best-effort, no puede tumbar /buscar."""
    clave = termino.strip().lower()
    if not clave:
        return None

    cacheada = _cache_imagenes.obtener(clave)
    if cacheada is not None:
        return cacheada or None

    imagen = await _buscar_imagen_sin_cache(termino)
    _cache_imagenes.guardar(clave, imagen or _SIN_IMAGEN)
    return imagen


async def _buscar_imagen_sin_cache(termino: str) -> Optional[str]:
    try:
        async with FarmatodoScraper(max_reintentos=2) as scraper:
            hit = await scraper._buscar_en_algolia(termino)  # noqa: SLF001 - reutilizado a propósito
    except Exception as exc:  # noqa: BLE001 - enriquecimiento best-effort, nunca debe romper /buscar
        logger.info("obtener_imagen_producto: no se pudo consultar Farmatodo para %r: %s", termino, exc)
        return None

    if hit is None:
        return None

    return hit.get("mediaImageUrl") or next(iter(hit.get("listUrlImages") or []), None)


async def obtener_imagenes_productos(terminos: list[str]) -> dict[str, Optional[str]]:
    """Versión en lote de `obtener_imagen_producto`: resuelve varias
    búsquedas en paralelo (una sola espera de red en vez de N
    secuenciales) para no penalizar la latencia cuando hay alternativas
    terapéuticas que también necesitan foto."""
    terminos_unicos = list(dict.fromkeys(t.strip() for t in terminos if t.strip()))
    if not terminos_unicos:
        return {}

    resultados = await asyncio.gather(*(obtener_imagen_producto(t) for t in terminos_unicos))
    return dict(zip(terminos_unicos, resultados))
