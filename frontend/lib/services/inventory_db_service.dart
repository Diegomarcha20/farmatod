import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/inventario.dart';

/// Base de datos SQLite del inventario propio de la tienda -separada
/// del caché de búsquedas de Farmatodo ([LocalCacheService]), porque es
/// un dato completamente distinto: no es un respaldo offline de algo
/// consultado, es información que el usuario crea y mantiene él mismo
/// (categorías con su tiempo de anticipación, productos bajo
/// seguimiento, lotes con vencimiento, y el conteo físico en curso).
class InventoryDbService {
  InventoryDbService._interno();

  static final InventoryDbService instancia = InventoryDbService._interno();

  Database? _db;

  Future<Database> _obtenerDb() async {
    final actual = _db;
    if (actual != null) return actual;

    final ruta = join(await getDatabasesPath(), 'farmatod_inventario.db');
    final db = await openDatabase(
      ruta,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categorias (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nombre TEXT NOT NULL UNIQUE,
            dias_anticipacion INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE productos (
            sku TEXT PRIMARY KEY,
            nombre TEXT NOT NULL,
            imagen_url TEXT,
            categoria_id INTEGER,
            cantidad_deposito INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (categoria_id) REFERENCES categorias(id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE lotes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sku TEXT NOT NULL,
            fecha_vencimiento TEXT NOT NULL,
            cantidad INTEGER NOT NULL DEFAULT 1,
            fecha_agregado INTEGER NOT NULL,
            FOREIGN KEY (sku) REFERENCES productos(sku) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE conteo_items (
            sku TEXT PRIMARY KEY,
            nombre TEXT NOT NULL,
            imagen_url TEXT,
            cantidad INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  // --------------------------------------------------------------------
  // Categorías de vencimiento
  // --------------------------------------------------------------------

  Future<List<CategoriaVencimiento>> listarCategorias() async {
    final db = await _obtenerDb();
    final filas = await db.query('categorias', orderBy: 'nombre COLLATE NOCASE');
    return filas.map(CategoriaVencimiento.fromMap).toList();
  }

  Future<CategoriaVencimiento> guardarCategoria({int? id, required String nombre, required int diasAnticipacion}) async {
    final db = await _obtenerDb();
    final datos = {'nombre': nombre.trim(), 'dias_anticipacion': diasAnticipacion};
    if (id == null) {
      final nuevoId = await db.insert('categorias', datos);
      return CategoriaVencimiento(id: nuevoId, nombre: datos['nombre'] as String, diasAnticipacion: diasAnticipacion);
    }
    await db.update('categorias', datos, where: 'id = ?', whereArgs: [id]);
    return CategoriaVencimiento(id: id, nombre: datos['nombre'] as String, diasAnticipacion: diasAnticipacion);
  }

  Future<void> borrarCategoria(int id) async {
    final db = await _obtenerDb();
    await db.update('productos', {'categoria_id': null}, where: 'categoria_id = ?', whereArgs: [id]);
    await db.delete('categorias', where: 'id = ?', whereArgs: [id]);
  }

  Future<CategoriaVencimiento?> obtenerCategoria(int id) async {
    final db = await _obtenerDb();
    final filas = await db.query('categorias', where: 'id = ?', whereArgs: [id], limit: 1);
    return filas.isEmpty ? null : CategoriaVencimiento.fromMap(filas.first);
  }

  // --------------------------------------------------------------------
  // Productos bajo seguimiento
  // --------------------------------------------------------------------

  Future<ProductoInventario?> obtenerProducto(String sku) async {
    final db = await _obtenerDb();
    final filas = await db.query('productos', where: 'sku = ?', whereArgs: [sku], limit: 1);
    return filas.isEmpty ? null : ProductoInventario.fromMap(filas.first);
  }

  Future<void> guardarProducto(ProductoInventario producto) async {
    final db = await _obtenerDb();
    await db.insert('productos', producto.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> actualizarCantidadDeposito(String sku, int cantidad) async {
    final db = await _obtenerDb();
    await db.update('productos', {'cantidad_deposito': cantidad}, where: 'sku = ?', whereArgs: [sku]);
  }

  Future<List<ProductoInventario>> listarProductos() async {
    final db = await _obtenerDb();
    final filas = await db.query('productos', orderBy: 'nombre COLLATE NOCASE');
    return filas.map(ProductoInventario.fromMap).toList();
  }

  // --------------------------------------------------------------------
  // Lotes con vencimiento
  // --------------------------------------------------------------------

  Future<LoteVencimiento> guardarLote({
    required String sku,
    required DateTime fechaVencimiento,
    required int cantidad,
  }) async {
    final db = await _obtenerDb();
    final ahora = DateTime.now();
    final datos = {
      'sku': sku,
      'fecha_vencimiento': fechaVencimiento.toIso8601String().split('T').first,
      'cantidad': cantidad,
      'fecha_agregado': ahora.millisecondsSinceEpoch,
    };
    final id = await db.insert('lotes', datos);
    return LoteVencimiento(
      id: id,
      sku: sku,
      fechaVencimiento: fechaVencimiento,
      cantidad: cantidad,
      fechaAgregado: ahora,
    );
  }

  Future<void> borrarLote(int loteId) async {
    final db = await _obtenerDb();
    await db.delete('lotes', where: 'id = ?', whereArgs: [loteId]);
  }

  /// Todos los lotes activos, ya combinados con su producto y
  /// categoría -para "Próximos a vencer"-.
  Future<List<LoteConDetalle>> listarLotesConDetalle() async {
    final db = await _obtenerDb();
    final filas = await db.rawQuery('''
      SELECT
        l.id AS lote_id, l.sku AS lote_sku, l.fecha_vencimiento, l.cantidad AS lote_cantidad,
        l.fecha_agregado,
        p.nombre AS producto_nombre, p.imagen_url, p.categoria_id, p.cantidad_deposito,
        c.id AS cat_id, c.nombre AS cat_nombre, c.dias_anticipacion
      FROM lotes l
      JOIN productos p ON p.sku = l.sku
      LEFT JOIN categorias c ON c.id = p.categoria_id
      ORDER BY l.fecha_vencimiento ASC
    ''');

    return filas.map((fila) {
      final lote = LoteVencimiento(
        id: fila['lote_id'] as int,
        sku: fila['lote_sku'] as String,
        fechaVencimiento: DateTime.parse(fila['fecha_vencimiento'] as String),
        cantidad: fila['lote_cantidad'] as int,
        fechaAgregado: DateTime.fromMillisecondsSinceEpoch(fila['fecha_agregado'] as int),
      );
      final producto = ProductoInventario(
        sku: lote.sku,
        nombre: fila['producto_nombre'] as String,
        imagenUrl: fila['imagen_url'] as String?,
        categoriaId: fila['categoria_id'] as int?,
        cantidadDeposito: fila['cantidad_deposito'] as int? ?? 0,
      );
      final categoria = fila['cat_id'] == null
          ? null
          : CategoriaVencimiento(
              id: fila['cat_id'] as int,
              nombre: fila['cat_nombre'] as String,
              diasAnticipacion: fila['dias_anticipacion'] as int,
            );
      return LoteConDetalle(lote: lote, producto: producto, categoria: categoria);
    }).toList();
  }

  // --------------------------------------------------------------------
  // Conteo físico en curso
  // --------------------------------------------------------------------

  Future<List<ConteoItem>> listarConteo() async {
    final db = await _obtenerDb();
    final filas = await db.query('conteo_items', orderBy: 'nombre COLLATE NOCASE');
    return filas.map(ConteoItem.fromMap).toList();
  }

  Future<ConteoItem> incrementarConteo(String sku, String nombre, String? imagenUrl, {int por = 1}) async {
    final db = await _obtenerDb();
    final existente = await db.query('conteo_items', where: 'sku = ?', whereArgs: [sku], limit: 1);
    final nuevaCantidad = existente.isEmpty ? por : (existente.first['cantidad'] as int) + por;
    final item = ConteoItem(sku: sku, nombre: nombre, imagenUrl: imagenUrl, cantidad: nuevaCantidad < 0 ? 0 : nuevaCantidad);
    await db.insert('conteo_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return item;
  }

  Future<void> quitarDelConteo(String sku) async {
    final db = await _obtenerDb();
    await db.delete('conteo_items', where: 'sku = ?', whereArgs: [sku]);
  }

  Future<void> vaciarConteo() async {
    final db = await _obtenerDb();
    await db.delete('conteo_items');
  }
}
