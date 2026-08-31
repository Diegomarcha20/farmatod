import 'package:flutter/foundation.dart';

import '../models/producto.dart';
import '../services/rate_config_service.dart';

/// Tasas de cambio manuales (Bs. -> divisa) configuradas por el
/// usuario en Ajustes, disponibles para toda la app vía `provider` sin
/// tener que releer SharedPreferences en cada pantalla. Se recarga
/// cada vez que se guardan tasas nuevas en Ajustes.
class RatesProvider extends ChangeNotifier {
  RatesProvider({RateConfigService? config}) : _config = config ?? RateConfigService.instancia {
    _cargar();
  }

  final RateConfigService _config;

  Map<String, TasaMoneda> tasas = Map<String, TasaMoneda>.from(RateConfigService.tasasPorDefecto);
  bool cargando = true;

  Future<void> _cargar() async {
    tasas = await _config.obtenerTasas();
    cargando = false;
    notifyListeners();
  }

  Future<void> guardar(Map<String, TasaMoneda> nuevasTasas) async {
    await _config.guardarTasas(nuevasTasas);
    tasas = await _config.obtenerTasas();
    notifyListeners();
  }

  /// Calcula el bloque de precios en divisas para un precio en Bs.
  /// usando las tasas manuales actuales -mismo cálculo que el backend
  /// (base + 3% IGTF, cada moneda con su propio modo), hecho en el
  /// propio teléfono-.
  ///
  /// Las monedas en modo [ModoTasa.multiplicarUsd] (ej. el peso
  /// colombiano vía dólar) se resuelven en un segundo paso, a partir
  /// del precio ya convertido a USD -por eso primero se calcula el de
  /// USD si está configurado-. Si una moneda pide ese modo pero "USD"
  /// no está configurado, esa moneda se omite del resultado en vez de
  /// mostrar un precio incorrecto.
  Map<String, PrecioDivisa> calcularPrecios(double precioBs) {
    final tasaUsd = tasas['USD'];
    final baseUsd = tasaUsd != null
        ? (tasaUsd.modo == ModoTasa.multiplicarBs ? precioBs * tasaUsd.valor : precioBs / tasaUsd.valor)
        : null;

    final resultado = <String, PrecioDivisa>{};
    for (final entrada in tasas.entries) {
      final codigo = entrada.key;
      final tasa = entrada.value;
      if (tasa.modo == ModoTasa.multiplicarUsd) {
        if (baseUsd == null) continue;
        resultado[codigo] = PrecioDivisa.desdeBase(baseUsd * tasa.valor);
      } else {
        resultado[codigo] = PrecioDivisa.calcular(precioBs, tasa.valor, multiplicar: tasa.modo == ModoTasa.multiplicarBs);
      }
    }
    return resultado;
  }
}
