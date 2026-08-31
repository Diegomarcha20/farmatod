import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tasas de cambio Bs. -> divisa, configuradas manualmente por el
/// usuario en Ajustes y persistidas en el propio teléfono
/// (SharedPreferences) -no dependen del backend ni se comparten entre
/// dispositivos-.
///
/// Convención (la misma que ya usa el backend): cada tasa es "cuántos
/// Bolívares equivalen a 1 unidad de esa moneda" (ej. "246.50" si 1
/// USD = Bs. 246,50). Se puede agregar cualquier código de moneda, no
/// solo USD/COP.
class RateConfigService {
  RateConfigService._interno();

  static final RateConfigService instancia = RateConfigService._interno();

  static const _claveTasas = 'tasas_cambio_manual';

  /// Valores de referencia mostrados la primera vez, antes de que el
  /// usuario configure nada en Ajustes -para que la app siga siendo
  /// útil de inmediato en vez de no mostrar ningún precio en divisas-.
  static const Map<String, double> tasasPorDefecto = {
    'USD': 200.0,
    'COP': 16.0,
  };

  Future<Map<String, double>> obtenerTasas() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveTasas);
    if (crudo == null || crudo.trim().isEmpty) {
      return Map<String, double>.from(tasasPorDefecto);
    }
    try {
      final decodificado = jsonDecode(crudo) as Map<String, dynamic>;
      final tasas = decodificado.map((codigo, valor) => MapEntry(codigo, (valor as num).toDouble()));
      return tasas.isEmpty ? Map<String, double>.from(tasasPorDefecto) : tasas;
    } catch (_) {
      return Map<String, double>.from(tasasPorDefecto);
    }
  }

  Future<bool> estaConfiguradoManualmente() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveTasas);
    return crudo != null && crudo.trim().isNotEmpty;
  }

  Future<void> guardarTasas(Map<String, double> tasas) async {
    final prefs = await SharedPreferences.getInstance();
    final limpio = <String, double>{
      for (final entrada in tasas.entries)
        if (entrada.key.trim().isNotEmpty && entrada.value > 0) entrada.key.trim().toUpperCase(): entrada.value,
    };
    await prefs.setString(_claveTasas, jsonEncode(limpio));
  }
}
