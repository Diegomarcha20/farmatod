/// Modelos del inventario propio de la tienda -a diferencia de
/// [Producto] (que refleja en vivo el catálogo público de Farmatodo),
/// todo esto vive SOLO en el teléfono: categorías con su tiempo de
/// anticipación antes de vencer, productos bajo seguimiento, lotes con
/// fecha de vencimiento, y el conteo físico. Nada de esto sale de
/// Farmatodo -no existe públicamente-, lo alimenta el propio usuario.
library;

/// Un tipo de producto con su propio tiempo de anticipación antes de
/// vencer (ej. "Chocolates" -> 30 días, "Champú" -> 60 días): cuántos
/// días antes de la fecha de vencimiento real hay que retirarlo del
/// anaquel, según el criterio de la tienda para ese tipo de producto.
class CategoriaVencimiento {
  const CategoriaVencimiento({
    required this.id,
    required this.nombre,
    required this.diasAnticipacion,
  });

  final int id;
  final String nombre;
  final int diasAnticipacion;

  factory CategoriaVencimiento.fromMap(Map<String, Object?> mapa) {
    return CategoriaVencimiento(
      id: mapa['id'] as int,
      nombre: mapa['nombre'] as String,
      diasAnticipacion: mapa['dias_anticipacion'] as int,
    );
  }

  Map<String, Object?> toMap({bool conId = true}) {
    return {
      if (conId) 'id': id,
      'nombre': nombre,
      'dias_anticipacion': diasAnticipacion,
    };
  }
}

/// Un producto bajo seguimiento de inventario propio (identificado por
/// SKU/código de barras). El nombre y la foto se autocompletan desde
/// el catálogo de Farmatodo cuando es posible (mismo mecanismo que la
/// búsqueda normal), pero el registro en sí -categoría, cantidad en
/// depósito- es enteramente propio de la tienda.
class ProductoInventario {
  const ProductoInventario({
    required this.sku,
    required this.nombre,
    this.imagenUrl,
    this.categoriaId,
    this.cantidadDeposito = 0,
  });

  final String sku;
  final String nombre;
  final String? imagenUrl;
  final int? categoriaId;
  final int cantidadDeposito;

  factory ProductoInventario.fromMap(Map<String, Object?> mapa) {
    return ProductoInventario(
      sku: mapa['sku'] as String,
      nombre: mapa['nombre'] as String,
      imagenUrl: mapa['imagen_url'] as String?,
      categoriaId: mapa['categoria_id'] as int?,
      cantidadDeposito: mapa['cantidad_deposito'] as int? ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'sku': sku,
      'nombre': nombre,
      'imagen_url': imagenUrl,
      'categoria_id': categoriaId,
      'cantidad_deposito': cantidadDeposito,
    };
  }

  ProductoInventario copyWith({
    String? nombre,
    String? imagenUrl,
    int? categoriaId,
    int? cantidadDeposito,
  }) {
    return ProductoInventario(
      sku: sku,
      nombre: nombre ?? this.nombre,
      imagenUrl: imagenUrl ?? this.imagenUrl,
      categoriaId: categoriaId ?? this.categoriaId,
      cantidadDeposito: cantidadDeposito ?? this.cantidadDeposito,
    );
  }
}

/// Un lote/tanda de un producto con su propia fecha de vencimiento
/// real y cantidad. Un mismo producto puede tener varios lotes activos
/// (llegadas en distintas fechas, con distinto vencimiento).
class LoteVencimiento {
  const LoteVencimiento({
    required this.id,
    required this.sku,
    required this.fechaVencimiento,
    required this.cantidad,
    required this.fechaAgregado,
  });

  /// También se usa como id de la notificación programada en el
  /// sistema operativo para este lote (1:1, sin necesidad de guardar
  /// un id aparte): al cancelar/reprogramar, se usa este mismo valor.
  final int id;
  final String sku;
  final DateTime fechaVencimiento;
  final int cantidad;
  final DateTime fechaAgregado;

  factory LoteVencimiento.fromMap(Map<String, Object?> mapa) {
    return LoteVencimiento(
      id: mapa['id'] as int,
      sku: mapa['sku'] as String,
      fechaVencimiento: DateTime.parse(mapa['fecha_vencimiento'] as String),
      cantidad: mapa['cantidad'] as int,
      fechaAgregado: DateTime.fromMillisecondsSinceEpoch(mapa['fecha_agregado'] as int),
    );
  }

  Map<String, Object?> toMap({bool conId = true}) {
    return {
      if (conId) 'id': id,
      'sku': sku,
      'fecha_vencimiento': fechaVencimiento.toIso8601String().split('T').first,
      'cantidad': cantidad,
      'fecha_agregado': fechaAgregado.millisecondsSinceEpoch,
    };
  }
}

/// Un lote ya combinado con los datos de su producto y categoría, listo
/// para mostrar en "Próximos a vencer" sin tener que resolver cada
/// referencia por separado en la UI.
class LoteConDetalle {
  const LoteConDetalle({
    required this.lote,
    required this.producto,
    required this.categoria,
  });

  final LoteVencimiento lote;
  final ProductoInventario producto;

  /// null si la categoría fue borrada después de asignada al lote.
  final CategoriaVencimiento? categoria;

  /// Fecha a partir de la cual hay que retirar el producto del
  /// anaquel: fecha de vencimiento real menos los días de anticipación
  /// de su categoría (0 si no tiene categoría asignada).
  DateTime get fechaAlerta =>
      lote.fechaVencimiento.subtract(Duration(days: categoria?.diasAnticipacion ?? 0));

  int diasParaAlerta(DateTime ahora) {
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final alerta = DateTime(fechaAlerta.year, fechaAlerta.month, fechaAlerta.day);
    return alerta.difference(hoy).inDays;
  }
}

/// Un renglón dentro de un conteo físico en curso: cuántas unidades se
/// han contado de un producto hasta el momento.
class ConteoItem {
  const ConteoItem({
    required this.sku,
    required this.nombre,
    this.imagenUrl,
    required this.cantidad,
  });

  final String sku;
  final String nombre;
  final String? imagenUrl;
  final int cantidad;

  factory ConteoItem.fromMap(Map<String, Object?> mapa) {
    return ConteoItem(
      sku: mapa['sku'] as String,
      nombre: mapa['nombre'] as String,
      imagenUrl: mapa['imagen_url'] as String?,
      cantidad: mapa['cantidad'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'sku': sku,
      'nombre': nombre,
      'imagen_url': imagenUrl,
      'cantidad': cantidad,
    };
  }

  ConteoItem copyWith({int? cantidad}) {
    return ConteoItem(sku: sku, nombre: nombre, imagenUrl: imagenUrl, cantidad: cantidad ?? this.cantidad);
  }
}
