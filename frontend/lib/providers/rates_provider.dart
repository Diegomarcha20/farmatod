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
  /// (base + 3% IGTF, cada moneda con su propio modo dividir/
  /// multiplicar), pero hecho en el propio teléfono-.
  Map<String, PrecioDivisa> calcularPrecios(double precioBs) {
    return tasas.map(
      (codigo, tasa) => MapEntry(codigo, PrecioDivisa.calcular(precioBs, tasa.valor, multiplicar: tasa.multiplicar)),
    );
  }
}
