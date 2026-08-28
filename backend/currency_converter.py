"""
currency_converter.py

Motor matemático de conversión multidivisa para precios extraídos en
Bolívares (Bs.), independiente del scraper. Calcula el monto en
CUALQUIER moneda que se configure manualmente (no solo USD/COP fijos)
aplicando el 3% de IGTF (Impuesto a las Grandes Transacciones
Financieras) vigente en Venezuela sobre pagos en divisas.

Convención de las tasas: cada moneda se define como "cuántos
Bolívares equivalen a 1 unidad de esa moneda" -el mismo tipo de número
que ya usabas para el dólar (ej. "246.50" si 1 USD = Bs. 246,50)-. Para
el peso colombiano en particular, esta convención además coincide con
cómo se cotiza el cambio directo Bs./COP en la frontera de Táchira, sin
necesidad de pasar por el dólar como intermediario.

Reglas de negocio implementadas, iguales para cualquier moneda:
  - Bs.: precio base exacto, sin IGTF (el IGTF solo aplica a pagos en
    divisas, no a pagos en moneda nacional).
  - Cada divisa configurada:
      base           = precio_bs / tasa_de_esa_moneda
      igtf_3pct      = base * 0.03
      total_con_igtf = base * 1.03

Las tasas se configuran manualmente (instanciando TasasConfiguracion)
o leyendo la variable de entorno TASAS_CAMBIO con
`TasasConfiguracion.desde_entorno()`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Union

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


def _normalizar_codigo(codigo: str) -> str:
    return codigo.strip().upper()


@dataclass(frozen=True)
class TasasConfiguracion:
    """Mapa de código de moneda -> cuántos Bolívares equivalen a 1
    unidad de esa moneda. No hay monedas "especiales" con lógica
    propia: agregar una nueva es agregar una entrada más al mapa, sin
    tocar código -así se admite "cualquier moneda", no solo USD/COP-.
    """

    tasas: dict[str, Decimal] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.tasas:
            raise TasaInvalidaError(
                "Debes configurar al menos una moneda (ej. USD) para poder "
                "calcular precios en divisas."
            )
        for codigo, tasa in self.tasas.items():
            if tasa <= 0:
                raise TasaInvalidaError(f"La tasa de {codigo} debe ser mayor a 0.")

    @classmethod
    def crear(cls, **tasas: Numero) -> "TasasConfiguracion":
        """Construye la configuración a partir de pares
        codigo=tasa, ej.:
            TasasConfiguracion.crear(USD="246.50", COP="16.67", EUR="268.30")
        Cada valor es "cuántos Bs. equivalen a 1 unidad de esa moneda"."""
        normalizado = {
            _normalizar_codigo(codigo): _a_decimal(tasa, f"tasa_{codigo}")
            for codigo, tasa in tasas.items()
            if tasa is not None
        }
        return cls(tasas=normalizado)

    @classmethod
    def desde_texto(cls, texto: str) -> "TasasConfiguracion":
        """Parsea el formato "USD:246.50,COP:16.67,EUR:268.30" (también
        acepta "=" en vez de ":", y espacios de sobra)."""
        tasas: dict[str, Decimal] = {}
        for par in texto.split(","):
            par = par.strip()
            if not par:
                continue
            separador = ":" if ":" in par else "="
            if separador not in par:
                raise TasaInvalidaError(
                    f'Formato inválido en "{par}" -usa "CODIGO:TASA", ej. "USD:246.50".'
                )
            codigo, _, tasa = par.partition(separador)
            codigo = _normalizar_codigo(codigo)
            if not codigo:
                raise TasaInvalidaError(f'Falta el código de moneda en "{par}".')
            tasas[codigo] = _a_decimal(tasa.strip(), f"tasa_{codigo}")
        return cls(tasas=tasas)

    @classmethod
    def desde_entorno(cls) -> "TasasConfiguracion":
        """Lee las tasas desde la variable de entorno TASAS_CAMBIO,
        formato "USD:246.50,COP:16.67" -agrega o quita monedas ahí,
        sin tocar código-."""
        texto = os.getenv("TASAS_CAMBIO")
        if not texto or not texto.strip():
            raise TasaInvalidaError(
                "La variable de entorno TASAS_CAMBIO es obligatoria, ej.: "
                '"USD:246.50,COP:16.67".'
            )
        return cls.desde_texto(texto)

    def monedas(self) -> list[str]:
        return list(self.tasas.keys())


def redondear_2_decimales(valor: Decimal) -> float:
    return float(valor.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def redondear_multiplo(valor: Decimal, multiplo: int) -> float:
    """Redondea `valor` al múltiplo comercial más cercano (p. ej. a la
    centena), útil para monedas con billetes/monedas grandes donde no
    tiene sentido cobrar centavos exactos."""
    unidad = Decimal(multiplo)
    pasos = (valor / unidad).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    return float(pasos * unidad)


def calcular_precio_divisa(precio_bs: Decimal, tasa: Decimal) -> dict:
    base = precio_bs / tasa
    igtf = base * IGTF_TASA
    total = base + igtf
    return {
        "base": redondear_2_decimales(base),
        "igtf_3pct": redondear_2_decimales(igtf),
        "total_con_igtf": redondear_2_decimales(total),
    }


def calcular_precios(precio_bs: Numero, tasas: TasasConfiguracion) -> dict:
    """Calcula el bloque `precios` completo (Bs. + una entrada por cada
    moneda configurada en `tasas`) a partir de un precio base en
    Bolívares, listo para insertarse en el JSON de respuesta."""
    precio_bs_decimal = _a_decimal(precio_bs, "precio_bs")
    if precio_bs_decimal < 0:
        raise TasaInvalidaError("precio_bs no puede ser negativo.")

    divisas = {
        codigo: calcular_precio_divisa(precio_bs_decimal, tasa)
        for codigo, tasa in tasas.tasas.items()
    }

    return {
        "bs": redondear_2_decimales(precio_bs_decimal),
        "divisas": divisas,
    }
