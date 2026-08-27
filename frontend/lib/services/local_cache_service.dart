import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/producto.dart';

/// Caché local en SQLite (en el propio dispositivo): guarda cada
/// producto que la app haya podido consultar exitosamente en el
/// backend (catálogo real de Farmatodo), para poder seguir mostrando
/// algo -nombre, precio, laboratorio- aunque no haya conexión. La
/// disponibilidad real y la ficha ampliada por IA NO se re-consultan
/// en modo offline: solo tienen sentido en tiempo real, así que se
/// muestra un aviso claro en vez de un dato potencialmente
/// desactualizado.
class LocalCacheService {
  LocalCacheService._interno();

  static final LocalCacheService instancia = LocalCacheService._interno();

  static const _nombreTabla = 'productos_cache';

  Database? _db;

  Future<Database> _obtenerDb() async {
    final actual = _db;
    if (actual != null) return actual;

    final ruta = join(await getDatabasesPath(), 'farmatod_cache.db');
    final db = await openDatabase(
      ruta,
      version: 4,
      onCreate: (db, version) async {
        await _crearTabla(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Es un caché desechable, no un dato con historial que
        // conservar: ante un cambio de esquema, es más simple y más
        // seguro recrear la tabla que migrar columna por columna.
        await db.execute('DROP TABLE IF EXISTS $_nombreTabla');
        await _crearTabla(db);
      },
    );
    _db = db;
    return db;
  }

  Future<void> _crearTabla(Database db) async {
    await db.execute('''
      CREATE TABLE $_nombreTabla (
        sku TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        principio_activo TEXT,
        categoria TEXT,
        descripcion TEXT,
        laboratorio TEXT,
        pais_origen TEXT,
        precio_bs REAL NOT NULL,
        precio_usd REAL NOT NULL,
        precio_cop REAL NOT NULL,
        en_stock INTEGER NOT NULL,
        cantidad_aproximada TEXT,
        ubicacion_planograma TEXT,
        sucursal TEXT NOT NULL,
        imagen_url TEXT,
        guardado_en INTEGER NOT NULL
      )
    ''');
  }

  /// Guarda (o reemplaza) un producto en el caché local. Se llama tras
  /// cada búsqueda exitosa contra el backend.
  Future<void> guardar(Producto producto) async {
    final db = await _obtenerDb();
    final datos = producto.toDbMap();
    datos['guardado_en'] = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      _nombreTabla,
      datos,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> guardarVarios(Iterable<Producto> productos) async {
    for (final producto in productos) {
      await guardar(producto);
    }
  }

  /// Busca en el caché local por SKU exacto o coincidencia parcial de
  /// nombre/principio activo. Devuelve el más reciente si hay varias
  /// coincidencias.
  Future<ProductoCacheado?> buscar(String termino) async {
    final db = await _obtenerDb();
    final terminoLimpio = termino.trim();
    if (terminoLimpio.isEmpty) return null;

    final filas = await db.rawQuery(
      '''
      SELECT * FROM $_nombreTabla
      WHERE sku = ?1 COLLATE NOCASE
         OR nombre LIKE '%' || ?1 || '%' COLLATE NOCASE
         OR principio_activo LIKE '%' || ?1 || '%' COLLATE NOCASE
      ORDER BY guardado_en DESC
      LIMIT 1
      ''',
      [terminoLimpio],
    );

    if (filas.isEmpty) return null;

    final fila = filas.first;
    final guardadoEnMs = fila['guardado_en'] as int;
    return ProductoCacheado(
      producto: Producto.fromDbMap(fila),
      guardadoEn: DateTime.fromMillisecondsSinceEpoch(guardadoEnMs),
    );
  }

  Future<int> contarProductos() async {
    final db = await _obtenerDb();
    final resultado = await db.rawQuery('SELECT COUNT(*) AS total FROM $_nombreTabla');
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}

/// Un producto recuperado del caché local, junto con el momento en que
/// se guardó -para poder avisar "dato de hace X minutos" en pantalla-.
class ProductoCacheado {
  const ProductoCacheado({required this.producto, required this.guardadoEn});

  final Producto producto;
  final DateTime guardadoEn;
}
