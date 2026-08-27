"""
Caché en memoria con expiración (TTL), reutilizable por cualquier
llamada "cara" del backend (IA, scraping, o cualquier integración
externa futura). No depende de Redis ni de infraestructura adicional:
para el volumen de una sola sucursal, un diccionario en memoria con
lock es suficiente y no añade nada que desplegar.

Se eligió esto en vez de `functools.lru_cache` porque `lru_cache` no
soporta expiración por tiempo (una entrada quedaría cacheada para
siempre hasta reiniciar el proceso), y aquí sí necesitamos que el dato
se refresque solo pasados los N minutos configurados.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Optional


class TTLCache:
    """Caché clave -> valor con expiración por tiempo y tamaño acotado.

    Thread-safe (protegida con un `Lock`) para que múltiples requests
    concurrentes de FastAPI/uvicorn puedan leer y escribir sin
    condiciones de carrera.
    """

    def __init__(self, ttl_segundos: int = 1800, max_entradas: int = 512) -> None:
        self._ttl = ttl_segundos
        self._max_entradas = max_entradas
        self._datos: dict[str, tuple[float, Any]] = {}
        self._lock = threading.Lock()
        self.aciertos = 0
        self.fallos = 0

    def obtener(self, clave: str) -> Optional[Any]:
        with self._lock:
            entrada = self._datos.get(clave)
            if entrada is None:
                self.fallos += 1
                return None

            guardado_en, valor = entrada
            if time.monotonic() - guardado_en > self._ttl:
                del self._datos[clave]
                self.fallos += 1
                return None

            self.aciertos += 1
            return valor

    def guardar(self, clave: str, valor: Any) -> None:
        with self._lock:
            if clave not in self._datos and len(self._datos) >= self._max_entradas:
                clave_mas_antigua = min(self._datos, key=lambda k: self._datos[k][0])
                del self._datos[clave_mas_antigua]
            self._datos[clave] = (time.monotonic(), valor)

    def invalidar(self, clave: str) -> None:
        with self._lock:
            self._datos.pop(clave, None)

    def limpiar(self) -> None:
        with self._lock:
            self._datos.clear()

    def estadisticas(self) -> dict:
        with self._lock:
            return {
                "entradas_activas": len(self._datos),
                "ttl_segundos": self._ttl,
                "aciertos": self.aciertos,
                "fallos": self.fallos,
            }
