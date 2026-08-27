import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/producto.dart';

/// Caché local en SQLite (en el propio dispositivo): guarda cada
/// producto que la app haya podido consultar exitosamente en el
/// backend, para poder seguir mostrando SKU y ubicación en el
/// planograma aunque el Wi-Fi de la tienda falle. La disponibilidad
/// (IA/scraping) NO se cachea aquí a propósito: solo tiene sentido en
/// tiempo real, así que en modo offline se muestra un aviso en vez de
/// un dato de stock potencialmente desactualizado.
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_nombreTabla (
            sku TEXT PRIMARY KEY,
            codigo_barras TEXT,
            nombre TEXT NOT NULL,
            principio_activo TEXT NOT NULL,
            categoria TEXT,
            descripcion TEXT,
            laboratorio TEXT,
            pais_origen TEXT,
            precio REAL NOT NULL,
            stock INTEGER NOT NULL,
            ubicacion_planograma TEXT NOT NULL,
            sucursal TEXT NOT NULL,
            imagen_url TEXT,
            imagen_referencial INTEGER NOT NULL DEFAULT 0,
            guardado_en INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_${_nombreTabla}_codigo_barras ON $_nombreTabla(codigo_barras)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_nombreTabla ADD COLUMN imagen_referencial INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE $_nombreTabla ADD COLUMN laboratorio TEXT');
          await db.execute('ALTER TABLE $_nombreTabla ADD COLUMN pais_origen TEXT');
        }
      },
    );
    _db = db;
    return db;
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

  /// Busca en el caché local por SKU exacto, código de barras exacto,
  /// o coincidencia parcial de nombre/principio activo -el mismo
  /// criterio flexible que usaría el backend-. Devuelve el más
  /// reciente si hay varias coincidencias.
  Future<ProductoCacheado?> buscar(String termino) async {
    final db = await _obtenerDb();
    final terminoLimpio = termino.trim();
    if (terminoLimpio.isEmpty) return null;

    final filas = await db.rawQuery(
      '''
      SELECT * FROM $_nombreTabla
      WHERE sku = ?1 COLLATE NOCASE
         OR codigo_barras = ?1
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
