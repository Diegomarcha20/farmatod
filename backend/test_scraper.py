"""
test_scraper.py

Script ejecutable directo (no requiere pytest) para probar en consola
la búsqueda de un medicamento real en Farmatodo Venezuela, mostrando
la disponibilidad en la sucursal "Arbolitos, San Cristóbal" y la tabla
de precios (Bs. / USD con IGTF / COP con IGTF) ya calculada.

Uso:
    python test_scraper.py
    python test_scraper.py "ibuprofeno 400"
    python test_scraper.py "paracetamol" --usd-bcv 246.50 --cop-usd 4050

Las tasas de cambio son configurables por línea de comandos; si se
omiten, se usan valores de ejemplo indicados explícitamente en pantalla
(reemplázalos por la tasa BCV y la tasa COP/USD vigentes el día que
ejecutes la prueba).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from decimal import Decimal

from currency_converter import TasaInvalidaError, TasasConfiguracion
from scraper_service import FarmatodoScraper, TiendaObjetivo

TASA_USD_BCV_EJEMPLO = Decimal("246.50")
TASA_COP_USD_EJEMPLO = Decimal("4050.00")


def _parsear_argumentos() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prueba de consulta en vivo a Farmatodo Venezuela con conversión multidivisa."
    )
    parser.add_argument(
        "termino",
        nargs="?",
        default="paracetamol",
        help="Nombre del medicamento a buscar (por defecto: 'paracetamol').",
    )
    parser.add_argument("--usd-bcv", type=str, default=str(TASA_USD_BCV_EJEMPLO), help="Tasa Bs./USD (BCV).")
    parser.add_argument("--cop-usd", type=str, default=str(TASA_COP_USD_EJEMPLO), help="Tasa COP/USD.")
    return parser.parse_args()


def _linea(caracter: str = "-", ancho: int = 58) -> str:
    return caracter * ancho


def _imprimir_encabezado(termino: str, tienda: TiendaObjetivo) -> None:
    print(_linea("="))
    print(f" FARMATODO VENEZUELA · Consulta de stock y precio")
    print(f" Sucursal fijada: {tienda.nombre_visible} (store_id={tienda.store_id}, city={tienda.city_id})")
    print(f" Búsqueda: \"{termino}\"")
    print(_linea("="))


def _imprimir_disponibilidad(resultado: dict) -> None:
    disponibilidad = resultado["disponibilidad"]
    estado = "EN STOCK" if disponibilidad["en_stock"] else "SIN STOCK"
    print(f"\nProducto : {resultado['nombre_comercial'] or '(no encontrado)'}")
    print(f"SKU      : {resultado['sku'] or '-'}")
    print(f"Tienda   : {disponibilidad['tienda']}")
    print(f"Estado   : {estado}  ({disponibilidad['cantidad_aproximada']})")
    if resultado.get("imagen_url"):
        print(f"Imagen   : {resultado['imagen_url']}")


def _imprimir_tabla_precios(precios: dict | None) -> None:
    print(f"\n{_linea()}")
    print(" TABLA DE PRECIOS")
    print(_linea())
    if precios is None:
        print(" (sin precio disponible)")
        return

    print(f" {'Moneda':<18}{'Base':>12}{'IGTF (3%)':>14}{'Total':>14}")
    print(_linea())
    print(f" {'Bolívares (Bs.)':<18}{precios['bs']:>12,.2f}{'—':>14}{precios['bs']:>14,.2f}")
    usd = precios["usd"]
    print(f" {'Dólares (USD)':<18}{usd['base']:>12,.2f}{usd['igtf_3pct']:>14,.2f}{usd['total_con_igtf']:>14,.2f}")
    cop = precios["cop"]
    print(f" {'Pesos Col. (COP)':<18}{cop['base']:>12,.2f}{cop['igtf_3pct']:>14,.2f}{cop['total_con_igtf']:>14,.2f}")
    print(_linea())


def _imprimir_advertencia(meta: dict) -> None:
    if meta.get("fuente") != "scraping_real":
        print(f"\n[!] Fuente de datos: {meta.get('fuente')}")
        if meta.get("advertencia"):
            print(f"    {meta['advertencia']}")


async def _ejecutar(termino: str, tasas: TasasConfiguracion) -> dict:
    tienda = TiendaObjetivo()
    _imprimir_encabezado(termino, tienda)

    async with FarmatodoScraper(tienda=tienda) as scraper:
        resultado = await scraper.buscar_producto(termino, tasas=tasas)

    _imprimir_disponibilidad(resultado)
    _imprimir_tabla_precios(resultado.get("precios"))
    _imprimir_advertencia(resultado["meta"])

    print(f"\n{_linea()}")
    print(" JSON CRUDO")
    print(_linea())
    print(json.dumps(resultado, indent=2, ensure_ascii=False))

    return resultado


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")

    argumentos = _parsear_argumentos()

    try:
        tasas = TasasConfiguracion.crear(
            tasa_usd_bcv=argumentos.usd_bcv,
            tasa_cop_usd=argumentos.cop_usd,
        )
    except TasaInvalidaError as exc:
        print(f"Error de configuración de tasas: {exc}", file=sys.stderr)
        return 1

    print(f"(Tasas usadas: 1 USD = {tasas.tasa_usd_bcv} Bs. | 1 USD = {tasas.tasa_cop_usd} COP)\n")

    try:
        asyncio.run(_ejecutar(argumentos.termino, tasas))
    except Exception as exc:  # noqa: BLE001 - el script de prueba tampoco debe reventar con traceback crudo
        print(f"\n[ERROR] La prueba no pudo completarse: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
