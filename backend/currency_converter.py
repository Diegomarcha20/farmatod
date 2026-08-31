"""
currency_converter.py

Motor matemático de conversión multidivisa para precios extraídos en
Bolívares (Bs.), independiente del scraper. Calcula el monto en
CUALQUIER moneda que se configure manualmente (no solo USD/COP fijos)
aplicando el 3% de IGTF (Impuesto a las Grandes Transacciones
Financieras) vigente en Venezuela sobre pagos en divisas.

Convención de las tasas: la mayoría de las monedas se cotizan como
"cuántos Bolívares equivalen a 1 unidad de esa moneda" -el mismo tipo
de número que ya usabas para el dólar (ej. "246.50" si 1 USD = Bs.
246,50)-, y para esas se DIVIDE el precio en Bs. entre la tasa. El
peso colombiano, en cambio, se cotiza al revés en la frontera de
Táchira -"cuántos pesos equivalen a 1 Bs." (ej. "16.67" si 1 Bs. = COP
16,67)-, así que para esa (o cualquier otra moneda que se cotice
igual) se MULTIPLICA en vez de dividir. Cada moneda declara su propio
modo -no hay una sola convención fija para todas-.

Reglas de negocio implementadas, iguales para cualquier moneda salvo
por el modo de cálculo:
  - Bs.: precio base exacto, sin IGTF (el IGTF solo aplica a pagos en
    divisas, no a pagos en moneda nacional).
  - Cada divisa configurada:
      base           = precio_bs / tasa   (modo "dividir", el default)
                        o precio_bs * tasa (modo "multiplicar")
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
class TasaMoneda:
    """Una tasa de cambio Bs./divisa, con su propio modo de cálculo.
    La mayoría de las monedas se cotizan como "cuántos Bs. equivalen a
    1 unidad de esa moneda" (modo dividir, el estándar de mercado
    cambiario -el que usa el dólar-). El peso colombiano en la
    frontera de Táchira se cotiza al revés -"cuántos pesos equivalen a
    1 Bs."- así que necesita multiplicar en vez de dividir. No hay
    monedas "especiales" con lógica propia en código: cada una declara
    su modo al configurar la tasa."""

    valor: Decimal
    multiplicar: bool = False

    def convertir(self, precio_bs: Decimal) -> Decimal:
        return precio_bs * self.valor if self.multiplicar else precio_bs / self.valor


@dataclass(frozen=True)
class TasasConfiguracion:
    """Mapa de código de moneda -> su [TasaMoneda] (valor + modo de
    cálculo). No hay monedas "especiales" con lógica propia en código:
    agregar una nueva es agregar una entrada más al mapa, sin tocar
    código -así se admite "cualquier moneda", no solo USD/COP-.
    """

    tasas: dict[str, TasaMoneda] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.tasas:
            raise TasaInvalidaError(
                "Debes configurar al menos una moneda (ej. USD) para poder "
                "calcular precios en divisas."
            )
        for codigo, tasa in self.tasas.items():
            if tasa.valor <= 0:
                raise TasaInvalidaError(f"La tasa de {codigo} debe ser mayor a 0.")

    @classmethod
    def crear(cls, **tasas: Numero) -> "TasasConfiguracion":
        """Construye la configuración a partir de pares
        codigo=tasa, ej.:
            TasasConfiguracion.crear(USD="246.50", EUR="268.30")
        Cada valor es "cuántos Bs. equivalen a 1 unidad de esa moneda"
        (modo dividir). Para el modo multiplicar (ej. peso colombiano),
        usa `desde_texto` con el separador "*"."""
        normalizado = {
            _normalizar_codigo(codigo): TasaMoneda(valor=_a_decimal(tasa, f"tasa_{codigo}"))
            for codigo, tasa in tasas.items()
            if tasa is not None
        }
        return cls(tasas=normalizado)

    @classmethod
    def desde_texto(cls, texto: str) -> "TasasConfiguracion":
        """Parsea el formato "USD:246.50,COP*16.67,EUR=268.30". El
        separador de cada par indica el modo de cálculo de esa moneda:
          ":" o "=" -> "cuántos Bs. equivalen a 1 unidad de esa
                       moneda" (dividir) -la convención estándar, la
                       que usa el dólar-.
          "*"       -> "cuántas unidades de esa moneda equivalen a 1
                       Bs." (multiplicar) -así se cotiza el peso
                       colombiano en la frontera de Táchira-.
        """
        tasas: dict[str, TasaMoneda] = {}
        for par in texto.split(","):
            par = par.strip()
            if not par:
                continue
            if "*" in par:
                separador, multiplicar = "*", True
            elif ":" in par:
                separador, multiplicar = ":", False
            elif "=" in par:
                separador, multiplicar = "=", False
            else:
                raise TasaInvalidaError(
                    f'Formato inválido en "{par}" -usa "CODIGO:TASA" (dividir) o '
                    '"CODIGO*TASA" (multiplicar), ej. "USD:246.50" o "COP*16.67".'
                )
            codigo, _, tasa = par.partition(separador)
            codigo = _normalizar_codigo(codigo)
            if not codigo:
                raise TasaInvalidaError(f'Falta el código de moneda en "{par}".')
            tasas[codigo] = TasaMoneda(
                valor=_a_decimal(tasa.strip(), f"tasa_{codigo}"),
                multiplicar=multiplicar,
            )
        return cls(tasas=tasas)

    @classmethod
    def desde_entorno(cls) -> "TasasConfiguracion":
        """Lee las tasas desde la variable de entorno TASAS_CAMBIO,
        formato "USD:246.50,COP*16.67" -agrega o quita monedas ahí,
        sin tocar código-."""
        texto = os.getenv("TASAS_CAMBIO")
        if not texto or not texto.strip():
            raise TasaInvalidaError(
                "La variable de entorno TASAS_CAMBIO es obligatoria, ej.: "
                '"USD:246.50,COP*16.67".'
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


def calcular_precio_divisa(precio_bs: Decimal, tasa: TasaMoneda) -> dict:
    base = tasa.convertir(precio_bs)
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
