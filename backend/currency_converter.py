"""
currency_converter.py

Motor matemático de conversión multidivisa para precios extraídos en
Bolívares (Bs.), independiente del scraper. Calcula el monto en
Dólares (USD) y Pesos Colombianos (COP) aplicando el 3% de IGTF
(Impuesto a las Grandes Transacciones Financieras) vigente en
Venezuela sobre pagos en divisas.

Reglas de negocio implementadas:
  - Bs.: precio base exacto, sin IGTF (el IGTF solo aplica a pagos en
    divisas, no a pagos en moneda nacional).
  - USD: base = precio_bs / tasa_usd_bcv
         igtf_3pct = base * 0.03
         total_con_igtf = base * 1.03
  - COP: base = usd_base * tasa_cop_usd  (o precio_bs * tasa_cop_ves
         si no se configuró tasa_cop_usd)
         igtf_3pct = base * 0.03
         total_con_igtf = redondeado a centenas/miles según el
         estándar comercial colombiano (ver `redondear_multiplo`).

Las tasas se configuran manualmente (instanciando TasasConfiguracion)
o leyendo variables de entorno con `TasasConfiguracion.desde_entorno()`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Optional, Union

IGTF_TASA = Decimal("0.03")

Numero = Union[int, float, str, Decimal]


class TasaInvalidaError(Exception):
    """Se lanza cuando una tasa de cambio o un precio configurado es inválido."""


def _a_decimal(valor: Numero, nombre_campo: str) -> Decimal:
    try:
        decimal_valor = valor if isinstance(valor, Decimal) else Decimal(str(valor))
    except (InvalidOperation, ValueError) as exc:
        raise TasaInvalidaError(f"{nombre_campo} no es un número válido: {valor!r}") from exc
    if decimal_valor.is_nan() or decimal_valor.is_infinite():
        raise TasaInvalidaError(f"{nombre_campo} no puede ser NaN o infinito.")
    return decimal_valor


@dataclass(frozen=True)
class TasasConfiguracion:
    """Tasas de cambio necesarias para el motor de conversión.

    Debe proveerse `tasa_cop_usd` (COP por 1 USD) o `tasa_cop_ves`
    (COP por 1 Bs.) para poder calcular la columna de Pesos
    Colombianos. Si se proveen ambas, se usa `tasa_cop_usd` por ser la
    referencia estándar del mercado cambiario.
    """

    tasa_usd_bcv: Decimal
    tasa_cop_usd: Optional[Decimal] = None
    tasa_cop_ves: Optional[Decimal] = None

    def __post_init__(self) -> None:
        if self.tasa_usd_bcv <= 0:
            raise TasaInvalidaError("tasa_usd_bcv debe ser mayor a 0.")
        if self.tasa_cop_usd is None and self.tasa_cop_ves is None:
            raise TasaInvalidaError(
                "Debes configurar tasa_cop_usd o tasa_cop_ves para poder "
                "calcular el precio en Pesos Colombianos."
            )
        if self.tasa_cop_usd is not None and self.tasa_cop_usd <= 0:
            raise TasaInvalidaError("tasa_cop_usd debe ser mayor a 0.")
        if self.tasa_cop_ves is not None and self.tasa_cop_ves <= 0:
            raise TasaInvalidaError("tasa_cop_ves debe ser mayor a 0.")

    @classmethod
    def crear(
        cls,
        tasa_usd_bcv: Numero,
        tasa_cop_usd: Optional[Numero] = None,
        tasa_cop_ves: Optional[Numero] = None,
    ) -> "TasasConfiguracion":
        """Construye la configuración validando y normalizando cada
        entrada (int, float, str o Decimal) a Decimal."""
        return cls(
            tasa_usd_bcv=_a_decimal(tasa_usd_bcv, "tasa_usd_bcv"),
            tasa_cop_usd=_a_decimal(tasa_cop_usd, "tasa_cop_usd") if tasa_cop_usd is not None else None,
            tasa_cop_ves=_a_decimal(tasa_cop_ves, "tasa_cop_ves") if tasa_cop_ves is not None else None,
        )

    @classmethod
    def desde_entorno(cls) -> "TasasConfiguracion":
        """Lee las tasas desde variables de entorno:
        TASA_USD_BCV (obligatoria), TASA_COP_USD y TASA_COP_VES
        (al menos una de las dos es obligatoria)."""
        tasa_usd = os.getenv("TASA_USD_BCV")
        if not tasa_usd:
            raise TasaInvalidaError(
                "La variable de entorno TASA_USD_BCV es obligatoria para "
                "calcular precios en divisas."
            )
        return cls.crear(
            tasa_usd_bcv=tasa_usd,
            tasa_cop_usd=os.getenv("TASA_COP_USD"),
            tasa_cop_ves=os.getenv("TASA_COP_VES"),
        )


def redondear_2_decimales(valor: Decimal) -> float:
    return float(valor.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def redondear_multiplo(valor: Decimal, multiplo: int) -> float:
    """Redondea `valor` al múltiplo comercial más cercano (p. ej. a la
    centena o al millar), como suele hacerse en Colombia al cobrar en
    efectivo por la escasez de denominaciones pequeñas."""
    unidad = Decimal(multiplo)
    pasos = (valor / unidad).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return float(pasos * unidad)


def _unidad_redondeo_cop(valor: Decimal) -> int:
    """Escoge una unidad de redondeo comercial según la magnitud del
    monto: centenas para montos pequeños, miles para montos grandes."""
    if valor < Decimal(100_000):
        return 100
    return 1000


def calcular_precio_usd(precio_bs: Decimal, tasa_usd_bcv: Decimal) -> dict:
    base = precio_bs / tasa_usd_bcv
    igtf = base * IGTF_TASA
    total = base + igtf
    return {
        "base": redondear_2_decimales(base),
        "igtf_3pct": redondear_2_decimales(igtf),
        "total_con_igtf": redondear_2_decimales(total),
    }


def calcular_precio_cop(
    precio_bs: Decimal,
    usd_base: Decimal,
    tasas: TasasConfiguracion,
    unidad_redondeo: Optional[int] = None,
) -> dict:
    if tasas.tasa_cop_usd is not None:
        base = usd_base * tasas.tasa_cop_usd
    else:
        base = precio_bs * tasas.tasa_cop_ves  # type: ignore[operator]

    igtf = base * IGTF_TASA
    total = base + igtf
    unidad = unidad_redondeo or _unidad_redondeo_cop(total)

    return {
        "base": redondear_2_decimales(base),
        "igtf_3pct": redondear_2_decimales(igtf),
        "total_con_igtf": redondear_multiplo(total, unidad),
    }


def calcular_precios(
    precio_bs: Numero,
    tasas: TasasConfiguracion,
    unidad_redondeo_cop: Optional[int] = None,
) -> dict:
    """Calcula el bloque `precios` completo (bs/usd/cop) a partir de un
    precio base en Bolívares, listo para insertarse en el JSON de
    respuesta del scraper."""
    precio_bs_decimal = _a_decimal(precio_bs, "precio_bs")
    if precio_bs_decimal < 0:
        raise TasaInvalidaError("precio_bs no puede ser negativo.")

    usd = calcular_precio_usd(precio_bs_decimal, tasas.tasa_usd_bcv)
    cop = calcular_precio_cop(
        precio_bs_decimal,
        Decimal(str(usd["base"])),
        tasas,
        unidad_redondeo=unidad_redondeo_cop,
    )

    return {
        "bs": redondear_2_decimales(precio_bs_decimal),
        "usd": usd,
        "cop": cop,
    }
