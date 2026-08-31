"""
currency_converter.py

Motor matemático de conversión multidivisa para precios extraídos en
Bolívares (Bs.), independiente del scraper. Calcula el monto en
CUALQUIER moneda que se configure manualmente (no solo USD/COP fijos)
aplicando el 3% de IGTF (Impuesto a las Grandes Transacciones
Financieras) vigente en Venezuela sobre pagos en divisas.

Convención de las tasas: cada moneda declara su propio modo de
cálculo, no hay una sola convención fija para todas:
  - "dividir_bs" (el default, ej. el dólar): la tasa es "cuántos
    Bolívares equivalen a 1 unidad de esa moneda" (ej. "246.50" si 1
    USD = Bs. 246,50) -> base = precio_bs / tasa.
  - "multiplicar_bs": la tasa es "cuántas unidades de esa moneda
    equivalen a 1 Bs." -> base = precio_bs * tasa.
  - "multiplicar_usd": la tasa es "cuántas unidades de esa moneda
    equivalen a 1 USD" (ej. "4000" si 1 USD = COP 4.000, la forma en
    que normalmente se conoce/cotiza el peso colombiano en la
    frontera, a través del dólar en vez de directo contra el Bs.) ->
    base = base_en_usd * tasa. Requiere que la moneda "USD" también
    esté configurada (en cualquier modo); si no, esa divisa se omite
    del resultado en vez de fallar toda la respuesta.

Reglas de negocio implementadas, iguales para cualquier moneda salvo
por el modo de cálculo:
  - Bs.: precio base exacto, sin IGTF (el IGTF solo aplica a pagos en
    divisas, no a pagos en moneda nacional).
  - Cada divisa configurada:
      base           = según su modo (ver arriba)
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
from enum import Enum
from typing import Optional, Union

IGTF_TASA = Decimal("0.03")

Numero = Union[int, float, str, Decimal]


class ModoTasa(str, Enum):
    DIVIDIR_BS = "dividir_bs"
    MULTIPLICAR_BS = "multiplicar_bs"
    MULTIPLICAR_USD = "multiplicar_usd"


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
    """Una tasa de cambio, con su propio modo de cálculo (ver
    [ModoTasa]). No hay monedas "especiales" con lógica propia en
    código: cada una declara su modo al configurar la tasa."""

    valor: Decimal
    modo: ModoTasa = ModoTasa.DIVIDIR_BS

    def convertir_desde_bs(self, precio_bs: Decimal) -> Decimal:
        """Solo válido para los modos que parten directo del precio en
        Bs. (`MULTIPLICAR_USD` se resuelve aparte en `calcular_precios`,
        porque necesita el precio ya convertido a USD, no el de Bs.)."""
        if self.modo is ModoTasa.MULTIPLICAR_BS:
            return precio_bs * self.valor
        return precio_bs / self.valor


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
        (modo dividir_bs). Para los otros modos, usa `desde_texto`."""
        normalizado = {
            _normalizar_codigo(codigo): TasaMoneda(valor=_a_decimal(tasa, f"tasa_{codigo}"))
            for codigo, tasa in tasas.items()
            if tasa is not None
        }
        return cls(tasas=normalizado)

    @classmethod
    def desde_texto(cls, texto: str) -> "TasasConfiguracion":
        """Parsea el formato "USD:246.50,COP%4000,EUR=268.30". El
        separador de cada par indica el modo de cálculo de esa moneda:
          ":" o "=" -> "cuántos Bs. equivalen a 1 unidad de esa
                       moneda" (dividir_bs) -la convención estándar,
                       la que usa el dólar-.
          "*"       -> "cuántas unidades de esa moneda equivalen a 1
                       Bs." (multiplicar_bs).
          "%"       -> "cuántas unidades de esa moneda equivalen a 1
                       USD" (multiplicar_usd) -así se suele conocer el
                       peso colombiano en la frontera de Táchira (ej.
                       "el dólar está en 4.000 pesos"), a través del
                       dólar en vez de directo contra el Bs.-. Requiere
                       que "USD" también esté configurado.
        """
        tasas: dict[str, TasaMoneda] = {}
        for par in texto.split(","):
            par = par.strip()
            if not par:
                continue
            if "%" in par:
                separador, modo = "%", ModoTasa.MULTIPLICAR_USD
            elif "*" in par:
                separador, modo = "*", ModoTasa.MULTIPLICAR_BS
            elif ":" in par:
                separador, modo = ":", ModoTasa.DIVIDIR_BS
            elif "=" in par:
                separador, modo = "=", ModoTasa.DIVIDIR_BS
            else:
                raise TasaInvalidaError(
                    f'Formato inválido en "{par}" -usa "CODIGO:TASA" (dividir contra Bs.), '
                    '"CODIGO*TASA" (multiplicar contra Bs.) o "CODIGO%TASA" (multiplicar '
                    'contra USD), ej. "USD:246.50" o "COP%4000".'
                )
            codigo, _, tasa = par.partition(separador)
            codigo = _normalizar_codigo(codigo)
            if not codigo:
                raise TasaInvalidaError(f'Falta el código de moneda en "{par}".')
            tasas[codigo] = TasaMoneda(
                valor=_a_decimal(tasa.strip(), f"tasa_{codigo}"),
                modo=modo,
            )
        return cls(tasas=tasas)

    @classmethod
    def desde_entorno(cls) -> "TasasConfiguracion":
        """Lee las tasas desde la variable de entorno TASAS_CAMBIO,
        formato "USD:246.50,COP%4000" -agrega o quita monedas ahí, sin
        tocar código-."""
        texto = os.getenv("TASAS_CAMBIO")
        if not texto or not texto.strip():
            raise TasaInvalidaError(
                "La variable de entorno TASAS_CAMBIO es obligatoria, ej.: "
                '"USD:246.50,COP%4000".'
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


def _precio_divisa_desde_base(base: Decimal) -> dict:
    igtf = base * IGTF_TASA
    total = base + igtf
    return {
        "base": redondear_2_decimales(base),
        "igtf_3pct": redondear_2_decimales(igtf),
        "total_con_igtf": redondear_2_decimales(total),
    }


def calcular_precio_divisa(precio_bs: Decimal, tasa: TasaMoneda) -> dict:
    """Solo válido para los modos que parten directo del precio en Bs.
    (ver `TasaMoneda.convertir_desde_bs`)."""
    return _precio_divisa_desde_base(tasa.convertir_desde_bs(precio_bs))


def calcular_precios(precio_bs: Numero, tasas: TasasConfiguracion) -> dict:
    """Calcula el bloque `precios` completo (Bs. + una entrada por cada
    moneda configurada en `tasas`) a partir de un precio base en
    Bolívares, listo para insertarse en el JSON de respuesta.

    Las monedas en modo `MULTIPLICAR_USD` (ej. el peso colombiano vía
    dólar) se resuelven en un segundo paso, a partir del precio base ya
    convertido a USD -por eso primero se calcula el de USD si está
    configurado-. Si una moneda pide ese modo pero "USD" no está
    configurado, esa moneda se omite del resultado en vez de romper
    toda la respuesta (las demás sí se calculan con normalidad)."""
    precio_bs_decimal = _a_decimal(precio_bs, "precio_bs")
    if precio_bs_decimal < 0:
        raise TasaInvalidaError("precio_bs no puede ser negativo.")

    tasa_usd = tasas.tasas.get("USD")
    base_usd: Optional[Decimal] = tasa_usd.convertir_desde_bs(precio_bs_decimal) if tasa_usd else None

    divisas: dict[str, dict] = {}
    for codigo, tasa in tasas.tasas.items():
        if tasa.modo is ModoTasa.MULTIPLICAR_USD:
            if base_usd is None:
                continue
            divisas[codigo] = _precio_divisa_desde_base(base_usd * tasa.valor)
        else:
            divisas[codigo] = calcular_precio_divisa(precio_bs_decimal, tasa)

    return {
        "bs": redondear_2_decimales(precio_bs_decimal),
        "divisas": divisas,
    }
