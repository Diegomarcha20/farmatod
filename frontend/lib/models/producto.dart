// Modelos de datos que reflejan las respuestas JSON del backend
// (FastAPI) del endpoint `/buscar`.
//
// El catálogo sale en tiempo real de Farmatodo Venezuela: por eso no
// hay un conteo exacto de stock (solo disponible/no disponible +
// "cantidad aproximada"), ni ubicación en planograma garantizada
// (Farmatodo no conoce el layout físico de una tienda de terceros), y
// el precio viene ya convertido a Bs./USD (con IGTF)/COP (con IGTF).

class Producto {
  final String sku;
  final String nombre;
  final String? principioActivo;
  final String? categoria;
  final String? descripcion;
  final String? laboratorio;
  final String? paisOrigen;
  final double precioBs;
  final double precioUsd;
  final double precioCop;
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
    required this.precioUsd,
    required this.precioCop,
    required this.enStock,
    required this.cantidadAproximada,
    this.ubicacionPlanograma,
    required this.sucursal,
    this.imagenUrl,
  });

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
      precioUsd: (json['precio_usd'] as num).toDouble(),
      precioCop: (json['precio_cop'] as num).toDouble(),
      enStock: json['en_stock'] as bool,
      cantidadAproximada: json['cantidad_aproximada'] as String? ?? '',
      ubicacionPlanograma: json['ubicacion_planograma'] as String?,
      sucursal: json['sucursal'] as String,
      imagenUrl: json['imagen_url'] as String?,
    );
  }

  /// Representación plana para guardar en el caché local (SQLite), que
  /// respalda la búsqueda cuando no hay conexión con el backend.
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
      'precio_usd': precioUsd,
      'precio_cop': precioCop,
      'en_stock': enStock ? 1 : 0,
      'cantidad_aproximada': cantidadAproximada,
      'ubicacion_planograma': ubicacionPlanograma,
      'sucursal': sucursal,
      'imagen_url': imagenUrl,
    };
  }

  factory Producto.fromDbMap(Map<String, Object?> mapa) {
    return Producto(
      sku: mapa['sku'] as String,
      nombre: mapa['nombre'] as String,
      principioActivo: mapa['principio_activo'] as String?,
      categoria: mapa['categoria'] as String?,
      descripcion: mapa['descripcion'] as String?,
      laboratorio: mapa['laboratorio'] as String?,
      paisOrigen: mapa['pais_origen'] as String?,
      precioBs: (mapa['precio_bs'] as num).toDouble(),
      precioUsd: (mapa['precio_usd'] as num).toDouble(),
      precioCop: (mapa['precio_cop'] as num).toDouble(),
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
