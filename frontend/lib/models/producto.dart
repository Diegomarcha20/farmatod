// Modelos de datos que reflejan las respuestas JSON del backend
// (FastAPI) del endpoint `/buscar`.

class Producto {
  final String sku;
  final String? codigoBarras;
  final String nombre;
  final String principioActivo;
  final String? categoria;
  final String? descripcion;
  final double precio;
  final int stock;
  final String ubicacionPlanograma;
  final String sucursal;
  final String? imagenUrl;

  /// true cuando `imagenUrl` es una foto real tomada del catálogo
  /// público de Farmatodo (por coincidencia de nombre), no
  /// necesariamente la misma presentación exacta que el SKU local.
  final bool imagenReferencial;

  const Producto({
    required this.sku,
    this.codigoBarras,
    required this.nombre,
    required this.principioActivo,
    this.categoria,
    this.descripcion,
    required this.precio,
    required this.stock,
    required this.ubicacionPlanograma,
    required this.sucursal,
    this.imagenUrl,
    this.imagenReferencial = false,
  });

  bool get tieneStock => stock > 0;

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      sku: json['sku'] as String,
      codigoBarras: json['codigo_barras'] as String?,
      nombre: json['nombre'] as String,
      principioActivo: json['principio_activo'] as String,
      categoria: json['categoria'] as String?,
      descripcion: json['descripcion'] as String?,
      precio: (json['precio'] as num).toDouble(),
      stock: json['stock'] as int,
      ubicacionPlanograma: json['ubicacion_planograma'] as String,
      sucursal: json['sucursal'] as String,
      imagenUrl: json['imagen_url'] as String?,
      imagenReferencial: json['imagen_referencial'] as bool? ?? false,
    );
  }

  /// Representación plana para guardar en el caché local (SQLite), que
  /// respalda la búsqueda cuando no hay conexión con el backend.
  Map<String, Object?> toDbMap() {
    return {
      'sku': sku,
      'codigo_barras': codigoBarras,
      'nombre': nombre,
      'principio_activo': principioActivo,
      'categoria': categoria,
      'descripcion': descripcion,
      'precio': precio,
      'stock': stock,
      'ubicacion_planograma': ubicacionPlanograma,
      'sucursal': sucursal,
      'imagen_url': imagenUrl,
      'imagen_referencial': imagenReferencial ? 1 : 0,
    };
  }

  factory Producto.fromDbMap(Map<String, Object?> mapa) {
    return Producto(
      sku: mapa['sku'] as String,
      codigoBarras: mapa['codigo_barras'] as String?,
      nombre: mapa['nombre'] as String,
      principioActivo: mapa['principio_activo'] as String,
      categoria: mapa['categoria'] as String?,
      descripcion: mapa['descripcion'] as String?,
      precio: (mapa['precio'] as num).toDouble(),
      stock: mapa['stock'] as int,
      ubicacionPlanograma: mapa['ubicacion_planograma'] as String,
      sucursal: mapa['sucursal'] as String,
      imagenUrl: mapa['imagen_url'] as String?,
      imagenReferencial: (mapa['imagen_referencial'] as int?) == 1,
    );
  }
}

class InfoSucursal {
  final String sucursal;
  final bool disponible;
  final int cantidad;
  final String? imagenUrl;
  final String fuente;

  const InfoSucursal({
    required this.sucursal,
    required this.disponible,
    required this.cantidad,
    this.imagenUrl,
    required this.fuente,
  });

  factory InfoSucursal.fromJson(Map<String, dynamic> json) {
    return InfoSucursal(
      sucursal: json['sucursal'] as String,
      disponible: json['disponible'] as bool,
      cantidad: json['cantidad'] as int,
      imagenUrl: json['imagen_url'] as String?,
      fuente: json['fuente'] as String,
    );
  }
}

class BuscarResponse {
  final bool encontrado;
  final String origen;
  final Producto? producto;
  final InfoSucursal? infoSucursal;
  final String? principioActivoDetectado;

  /// Varias coincidencias posibles (por nombre, principio activo o
  /// síntoma) cuando ninguna es claramente LA respuesta. Cuando no está
  /// vacío, `producto` es null: hay que elegir una y volver a buscar
  /// por su SKU exacto para obtener disponibilidad y precio real.
  final List<Producto> opciones;
  final List<Producto> alternativas;
  final String? mensaje;

  const BuscarResponse({
    required this.encontrado,
    required this.origen,
    this.producto,
    this.infoSucursal,
    this.principioActivoDetectado,
    this.opciones = const [],
    this.alternativas = const [],
    this.mensaje,
  });

  /// Considera el stock reportado por la sucursal (scraping) si está
  /// disponible; si no, cae al stock de la base local.
  int get stockEfectivo => infoSucursal?.cantidad ?? producto?.stock ?? 0;

  bool get esDetectadoPorIA => origen == 'ia_gemini';

  factory BuscarResponse.fromJson(Map<String, dynamic> json) {
    return BuscarResponse(
      encontrado: json['encontrado'] as bool,
      origen: json['origen'] as String,
      producto: json['producto'] != null
          ? Producto.fromJson(json['producto'] as Map<String, dynamic>)
          : null,
      infoSucursal: json['info_sucursal'] != null
          ? InfoSucursal.fromJson(json['info_sucursal'] as Map<String, dynamic>)
          : null,
      principioActivoDetectado: json['principio_activo_detectado'] as String?,
      opciones: (json['opciones'] as List<dynamic>? ?? [])
          .map((e) => Producto.fromJson(e as Map<String, dynamic>))
          .toList(),
      alternativas: (json['alternativas'] as List<dynamic>? ?? [])
          .map((e) => Producto.fromJson(e as Map<String, dynamic>))
          .toList(),
      mensaje: json['mensaje'] as String?,
    );
  }
}
