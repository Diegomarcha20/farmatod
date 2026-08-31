import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Modo de cálculo de una tasa de cambio -cada moneda declara el suyo,
/// no hay una sola convención fija para todas-.
enum ModoTasa {
  /// La tasa es "cuántos Bs. equivalen a 1 unidad de esa moneda" (el
  /// estándar de mercado cambiario, ej. el dólar). base = Bs./tasa.
  dividirBs,

  /// La tasa es "cuántas unidades de esa moneda equivalen a 1 Bs.".
  /// base = Bs.*tasa.
  multiplicarBs,

  /// La tasa es "cuántas unidades de esa moneda equivalen a 1 USD"
  /// -así se suele conocer el peso colombiano en la frontera de
  /// Táchira (ej. "el dólar está en 4.000 pesos"), a través del dólar
  /// en vez de directo contra el Bs.-. base = base_en_usd*tasa.
  /// Requiere que la moneda "USD" también esté configurada.
  multiplicarUsd;

  static ModoTasa desdeJson(String? valor) {
    return ModoTasa.values.firstWhere((m) => m.name == valor, orElse: () => ModoTasa.dividirBs);
  }
}

/// Una tasa de cambio Bs./divisa, con su propio modo de cálculo -ver
/// [ModoTasa]-.
class TasaMoneda {
  const TasaMoneda({required this.valor, this.modo = ModoTasa.dividirBs});

  final double valor;
  final ModoTasa modo;

  factory TasaMoneda.fromJson(Map<String, dynamic> json) {
    return TasaMoneda(
      valor: (json['valor'] as num).toDouble(),
      modo: ModoTasa.desdeJson(json['modo'] as String?),
    );
  }

  Map<String, Object?> toJson() => {'valor': valor, 'modo': modo.name};
}

/// Tasas de cambio Bs. -> divisa, configuradas manualmente por el
/// usuario en Ajustes y persistidas en el propio teléfono
/// (SharedPreferences) -no dependen del backend ni se comparten entre
/// dispositivos-. Se puede agregar cualquier código de moneda, no solo
/// USD/COP.
class RateConfigService {
  RateConfigService._interno();

  static final RateConfigService instancia = RateConfigService._interno();

  static const _claveTasas = 'tasas_cambio_manual_v3';

  /// Valores de referencia mostrados la primera vez, antes de que el
  /// usuario configure nada en Ajustes -para que la app siga siendo
  /// útil de inmediato en vez de no mostrar ningún precio en divisas-.
  /// El peso colombiano por defecto vía dólar, que es como normalmente
  /// se conoce su cotización en la frontera.
  static const Map<String, TasaMoneda> tasasPorDefecto = {
    'USD': TasaMoneda(valor: 200.0),
    'COP': TasaMoneda(valor: 4000.0, modo: ModoTasa.multiplicarUsd),
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
