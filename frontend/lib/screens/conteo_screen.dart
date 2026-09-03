import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/api_service.dart';
import '../services/inventory_db_service.dart';
import '../widgets/product_card.dart';
import 'scanner_screen.dart';

/// Conteo físico con precisión: cada escaneo suma 1 unidad al total de
/// ese producto -en vez de tener que teclear el número a mano y
/// arriesgarse a un typo o a perder la cuenta-. Queda guardado en el
/// teléfono aunque se cierre la app a medio conteo, y "Finalizar" lo
/// vuelca como la cantidad en depósito de cada producto.
class ConteoScreen extends StatefulWidget {
  const ConteoScreen({super.key});

  @override
  State<ConteoScreen> createState() => _ConteoScreenState();
}

class _ConteoScreenState extends State<ConteoScreen> {
  final _api = ApiService();
  final _db = InventoryDbService.instancia;

  List<ConteoItem> _items = [];
  bool _cargando = true;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final items = await _db.listarConteo();
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (codigo == null || codigo.isEmpty || !mounted) return;
    await _sumar(codigo);
  }

  Future<void> _sumar(String termino) async {
    setState(() => _procesando = true);
    try {
      // Primero contra lo que ya está en este conteo o registrado
      // localmente -no hace falta red para seguir sumando lo que ya se
      // identificó una vez-, y solo si no se conoce, se consulta a
      // Farmatodo para obtener nombre/foto.
      final yaEnConteo = _items.where((i) => i.sku == termino).toList();
      final registrado = await _db.obtenerProducto(termino);

      String nombre;
      String? imagenUrl;
      String sku;

      if (yaEnConteo.isNotEmpty) {
        sku = yaEnConteo.first.sku;
        nombre = yaEnConteo.first.nombre;
        imagenUrl = yaEnConteo.first.imagenUrl;
      } else if (registrado != null) {
        sku = registrado.sku;
        nombre = registrado.nombre;
        imagenUrl = registrado.imagenUrl;
      } else {
        final resultado = await _api.buscar(termino);
        final encontrado = resultado.producto ?? (resultado.opciones.isNotEmpty ? resultado.opciones.first : null);
        if (encontrado == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se reconoció ese código -no está en Farmatodo ni registrado.')),
            );
          }
          return;
        }
        sku = encontrado.sku;
        nombre = encontrado.nombre;
        imagenUrl = encontrado.imagenUrl;
      }

      await _db.incrementarConteo(sku, nombre, imagenUrl);
      await _cargar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo procesar el escaneo. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _ajustar(ConteoItem item, int delta) async {
    await _db.incrementarConteo(item.sku, item.nombre, item.imagenUrl, por: delta);
    _cargar();
  }

  Future<void> _quitar(ConteoItem item) async {
    await _db.quitarDelConteo(item.sku);
    _cargar();
  }

  Future<void> _finalizar() async {
    if (_items.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Finalizar conteo?'),
        content: Text(
          'Se van a guardar estas ${_items.length} cantidades como el stock actual '
          'en depósito, y se vacía este conteo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmar != true) return;

    for (final item in _items) {
      final existente = await _db.obtenerProducto(item.sku);
      await _db.guardarProducto(
        (existente ?? ProductoInventario(sku: item.sku, nombre: item.nombre, imagenUrl: item.imagenUrl))
            .copyWith(cantidadDeposito: item.cantidad),
      );
    }
    await _db.vaciarConteo();
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conteo guardado como stock de depósito.')),
    );
  }

  int get _totalUnidades => _items.fold(0, (suma, i) => suma + i.cantidad);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conteo')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _procesando ? null : _escanear,
                        icon: _procesando
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(_procesando ? 'Procesando...' : 'Escanear producto'),
                      ),
                    ),
                  ),
                  if (_items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_items.length} productos · $_totalUnidades unidades',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary.withValues(alpha: 0.6)),
                          ),
                          TextButton(onPressed: _finalizar, child: const Text('Finalizar conteo')),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Escanea cada producto que cuentes -cada escaneo suma 1 unidad automáticamente-.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary.withValues(alpha: 0.5)),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final item = _items[i];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      ProductoImagen(url: item.imagenUrl, tamano: 48),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.nombre,
                                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _ajustar(item, -1),
                                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                                        color: AppColors.primary.withValues(alpha: 0.5),
                                      ),
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          '${item.cantidad}',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _ajustar(item, 1),
                                        icon: const Icon(Icons.add_circle_outline, size: 20),
                                        color: AppColors.primary.withValues(alpha: 0.5),
                                      ),
                                      IconButton(
                                        onPressed: () => _quitar(item),
                                        icon: const Icon(Icons.close, size: 18),
                                        color: AppColors.stockAgotado.withValues(alpha: 0.7),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
