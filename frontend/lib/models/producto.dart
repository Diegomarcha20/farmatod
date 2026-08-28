// Modelos de datos que reflejan las respuestas JSON del backend
// (FastAPI) del endpoint `/buscar`.
//
// El catálogo sale en tiempo real de Farmatodo Venezuela: por eso no
// hay un conteo exacto de stock (solo disponible/no disponible +
// "cantidad aproximada"), ni ubicación en planograma garantizada
// (Farmatodo no conoce el layout físico de una tienda de terceros), y
// el precio viene ya convertido a Bs. + CUALQUIER moneda que el
// usuario haya configurado manualmente en el backend (con IGTF), no
// solo USD/COP fijos.

import 'dart:convert';

/// Precio ya convertido a una divisa concreta (con y sin IGTF).
class PrecioDivisa {
  final double base;
  final double igtf3pct;
  final double totalConIgtf;

  const PrecioDivisa({
    required this.base,
    required this.igtf3pct,
    required this.totalConIgtf,
  });

  factory PrecioDivisa.fromJson(Map<String, dynamic> json) {
    return PrecioDivisa(
      base: (json['base'] as num).toDouble(),
      igtf3pct: (json['igtf_3pct'] as num).toDouble(),
      totalConIgtf: (json['total_con_igtf'] as num).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {
        'base': base,
        'igtf_3pct': igtf3pct,
        'total_con_igtf': totalConIgtf,
      };
}

class Producto {
  final String sku;
  final String nombre;
  final String? principioActivo;
  final String? categoria;
  final String? descripcion;
  final String? laboratorio;
  final String? paisOrigen;
  final double precioBs;

  /// Una entrada por cada moneda configurada en el backend (ej. "USD",
  /// "COP", o cualquier otra) -sin límite fijo de monedas-.
  final Map<String, PrecioDivisa> precios;
  final bool enStock;
  final String cantidadAproximada;
  final String? ubicacionPlanograma;
  final String sucursal;
  final String? imagenUrl;

  const Producto({
    required this.sku,
    required this.nombre,
    this.principioActivo,
    this.categoria,
    this.descripcion,
    this.laboratorio,
    this.paisOrigen,
    required this.precioBs,
    required this.precios,
    required this.enStock,
    required this.cantidadAproximada,
    this.ubicacionPlanograma,
    required this.sucursal,
    this.imagenUrl,
  });

  static Map<String, PrecioDivisa> _precioDivisasFromJson(dynamic json) {
    final mapa = json as Map<String, dynamic>? ?? const {};
    return mapa.map(
      (codigo, valor) => MapEntry(codigo, PrecioDivisa.fromJson(valor as Map<String, dynamic>)),
    );
  }

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      sku: json['sku'] as String,
      nombre: json['nombre'] as String,
      principioActivo: json['principio_activo'] as String?,
      categoria: json['categoria'] as String?,
      descripcion: json['descripcion'] as String?,
      laboratorio: json['laboratorio'] as String?,
      paisOrigen: json['pais_origen'] as String?,
      precioBs: (json['precio_bs'] as num).toDouble(),
      precios: _precioDivisasFromJson(json['precios']),
      enStock: json['en_stock'] as bool,
      cantidadAproximada: json['cantidad_aproximada'] as String? ?? '',
      ubicacionPlanograma: json['ubicacion_planograma'] as String?,
      sucursal: json['sucursal'] as String,
      imagenUrl: json['imagen_url'] as String?,
    );
  }

  /// Representación plana para guardar en el caché local (SQLite), que
  /// respalda la búsqueda cuando no hay conexión con el backend. El
  /// mapa de divisas (variable en cantidad/monedas) se serializa como
  /// JSON en una sola columna de texto.
  Map<String, Object?> toDbMap() {
    return {
      'sku': sku,
      'nombre': nombre,
      'principio_activo': principioActivo,
      'categoria': categoria,
      'descripcion': descripcion,
      'laboratorio': laboratorio,
      'pais_origen': paisOrigen,
      'precio_bs': precioBs,
      'precios_json': jsonEncode(precios.map((codigo, p) => MapEntry(codigo, p.toJson()))),
      'en_stock': enStock ? 1 : 0,
      'cantidad_aproximada': cantidadAproximada,
      'ubicacion_planograma': ubicacionPlanograma,
      'sucursal': sucursal,
      'imagen_url': imagenUrl,
    };
  }

  factory Producto.fromDbMap(Map<String, Object?> mapa) {
    final precioJson = mapa['precios_json'] as String?;
    return Producto(
      sku: mapa['sku'] as String,
      nombre: mapa['nombre'] as String,
      principioActivo: mapa['principio_activo'] as String?,
      categoria: mapa['categoria'] as String?,
      descripcion: mapa['descripcion'] as String?,
      laboratorio: mapa['laboratorio'] as String?,
      paisOrigen: mapa['pais_origen'] as String?,
      precioBs: (mapa['precio_bs'] as num).toDouble(),
      precios: precioJson != null && precioJson.isNotEmpty
          ? _precioDivisasFromJson(jsonDecode(precioJson) as Map<String, dynamic>)
          : const {},
      enStock: (mapa['en_stock'] as int?) == 1,
      cantidadAproximada: mapa['cantidad_aproximada'] as String? ?? '',
      ubicacionPlanograma: mapa['ubicacion_planograma'] as String?,
      sucursal: mapa['sucursal'] as String,
      imagenUrl: mapa['imagen_url'] as String?,
    );
  }
}

class BuscarResponse {
  final bool encontrado;
  final String origen;
  final Producto? producto;
  final String? principioActivoDetectado;

  /// Varias coincidencias posibles (por nombre, principio activo o
  /// síntoma): sin límite, todas las que haya en el catálogo real de
  /// Farmatodo. Cuando no está vacío, `producto` es null: hay que
  /// elegir una y volver a buscar por su nombre/SKU exacto.
  final List<Producto> opciones;
  final List<Producto> alternativas;
  final String? fuente;
  final String? mensaje;

  const BuscarResponse({
    required this.encontrado,
    required this.origen,
    this.producto,
    this.principioActivoDetectado,
    this.opciones = const [],
    this.alternativas = const [],
    this.fuente,
    this.mensaje,
  });

  bool get esDetectadoPorIA => origen == 'ia_gemini';

  factory BuscarResponse.fromJson(Map<String, dynamic> json) {
    return BuscarResponse(
      encontrado: json['encontrado'] as bool,
      origen: json['origen'] as String,
      producto: json['producto'] != null
          ? Producto.fromJson(json['producto'] as Map<String, dynamic>)
          : null,
      principioActivoDetectado: json['principio_activo_detectado'] as String?,
      opciones: (json['opciones'] as List<dynamic>? ?? [])
          .map((e) => Producto.fromJson(e as Map<String, dynamic>))
          .toList(),
      alternativas: (json['alternativas'] as List<dynamic>? ?? [])
          .map((e) => Producto.fromJson(e as Map<String, dynamic>))
          .toList(),
      fuente: json['fuente'] as String?,
      mensaje: json['mensaje'] as String?,
    );
  }
}
