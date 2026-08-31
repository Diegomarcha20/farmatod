import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Una tasa de cambio Bs./divisa, con su propio modo de cálculo. La
/// mayoría de las monedas se cotizan como "cuántos Bs. equivalen a 1
/// unidad de esa moneda" (modo dividir, el default -la convención
/// estándar, la que usa el dólar-). El peso colombiano se cotiza al
/// revés en la frontera de Táchira -"cuántos pesos equivalen a 1 Bs."
/// (modo multiplicar)-, así que cada moneda declara su propio modo en
/// vez de asumir uno fijo para todas.
class TasaMoneda {
  const TasaMoneda({required this.valor, this.multiplicar = false});

  final double valor;
  final bool multiplicar;

  factory TasaMoneda.fromJson(Map<String, dynamic> json) {
    return TasaMoneda(
      valor: (json['valor'] as num).toDouble(),
      multiplicar: json['multiplicar'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {'valor': valor, 'multiplicar': multiplicar};
}

/// Tasas de cambio Bs. -> divisa, configuradas manualmente por el
/// usuario en Ajustes y persistidas en el propio teléfono
/// (SharedPreferences) -no dependen del backend ni se comparten entre
/// dispositivos-. Se puede agregar cualquier código de moneda, no solo
/// USD/COP.
class RateConfigService {
  RateConfigService._interno();

  static final RateConfigService instancia = RateConfigService._interno();

  static const _claveTasas = 'tasas_cambio_manual_v2';

  /// Valores de referencia mostrados la primera vez, antes de que el
  /// usuario configure nada en Ajustes -para que la app siga siendo
  /// útil de inmediato en vez de no mostrar ningún precio en divisas-.
  static const Map<String, TasaMoneda> tasasPorDefecto = {
    'USD': TasaMoneda(valor: 200.0),
    'COP': TasaMoneda(valor: 16.0, multiplicar: true),
  };

  Future<Map<String, TasaMoneda>> obtenerTasas() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveTasas);
    if (crudo == null || crudo.trim().isEmpty) {
      return Map<String, TasaMoneda>.from(tasasPorDefecto);
    }
    try {
      final decodificado = jsonDecode(crudo) as Map<String, dynamic>;
      final tasas = decodificado.map(
        (codigo, valor) => MapEntry(codigo, TasaMoneda.fromJson(valor as Map<String, dynamic>)),
      );
      return tasas.isEmpty ? Map<String, TasaMoneda>.from(tasasPorDefecto) : tasas;
    } catch (_) {
      return Map<String, TasaMoneda>.from(tasasPorDefecto);
    }
  }

  Future<bool> estaConfiguradoManualmente() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveTasas);
    return crudo != null && crudo.trim().isNotEmpty;
  }

  Future<void> guardarTasas(Map<String, TasaMoneda> tasas) async {
    final prefs = await SharedPreferences.getInstance();
    final limpio = <String, TasaMoneda>{
      for (final entrada in tasas.entries)
        if (entrada.key.trim().isNotEmpty && entrada.value.valor > 0) entrada.key.trim().toUpperCase(): entrada.value,
    };
    await prefs.setString(_claveTasas, jsonEncode(limpio.map((codigo, tasa) => MapEntry(codigo, tasa.toJson()))));
  }
}
