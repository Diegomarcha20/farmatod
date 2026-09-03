import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/api_service.dart';
import '../services/inventory_db_service.dart';
import '../services/notification_service.dart';
import 'categorias_screen.dart';
import 'scanner_screen.dart';

/// Agrega un producto a seguimiento de vencimiento: se identifica por
/// código de barras (cámara) o nombre -autocompletando foto/nombre
/// desde el catálogo de Farmatodo cuando se encuentra, editable a
/// mano si no-, se le asigna una categoría (con su propio tiempo de
/// anticipación) y se anota la fecha de vencimiento real del lote. Al
/// guardar, programa la notificación en el teléfono para la fecha de
/// alerta calculada (vencimiento - anticipación de la categoría).
class AgregarLoteScreen extends StatefulWidget {
  const AgregarLoteScreen({super.key});

  @override
  State<AgregarLoteScreen> createState() => _AgregarLoteScreenState();
}

class _AgregarLoteScreenState extends State<AgregarLoteScreen> {
  final _api = ApiService();
  final _db = InventoryDbService.instancia;

  final _skuController = TextEditingController();
  final _nombreController = TextEditingController();
  final _cantidadController = TextEditingController(text: '1');

  String? _imagenUrl;
  int? _categoriaId;
  DateTime? _fechaVencimiento;
  List<CategoriaVencimiento> _categorias = [];

  bool _cargandoCategorias = true;
  bool _buscandoEnFarmatodo = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nombreController.dispose();
    _cantidadController.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    final categorias = await _db.listarCategorias();
    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      if (_categoriaId != null && categorias.every((c) => c.id != _categoriaId)) {
        _categoriaId = null;
      }
      _cargandoCategorias = false;
    });
  }

  Future<void> _irACategorias() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriasScreen()));
    await _cargarCategorias();
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (codigo == null || codigo.isEmpty || !mounted) return;
    _skuController.text = codigo;
    await _buscarEnFarmatodo();
  }

  Future<void> _buscarEnFarmatodo() async {
    final termino = _skuController.text.trim();
    if (termino.isEmpty) return;

    setState(() => _buscandoEnFarmatodo = true);
    try {
      final resultado = await _api.buscar(termino);
      final encontrado = resultado.producto ?? (resultado.opciones.isNotEmpty ? resultado.opciones.first : null);
      if (!mounted) return;
      if (encontrado != null) {
        setState(() {
          _skuController.text = encontrado.sku;
          _nombreController.text = encontrado.nombre;
          _imagenUrl = encontrado.imagenUrl;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró en Farmatodo — escribe el nombre manualmente.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo consultar Farmatodo — escribe el nombre manualmente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoEnFarmatodo = false);
    }
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaVencimiento ?? ahora.add(const Duration(days: 30)),
      firstDate: ahora.subtract(const Duration(days: 365)),
      lastDate: ahora.add(const Duration(days: 365 * 5)),
      helpText: 'Fecha de vencimiento del lote',
    );
    if (fecha != null) setState(() => _fechaVencimiento = fecha);
  }

  Future<void> _guardar() async {
    final sku = _skuController.text.trim();
    final nombre = _nombreController.text.trim();
    final cantidad = int.tryParse(_cantidadController.text.trim()) ?? 1;

    if (sku.isEmpty || nombre.isEmpty) {
      setState(() => _error = 'Escanea o escribe el código de barras y el nombre del producto.');
      return;
    }
    if (_categoriaId == null) {
      setState(() => _error = 'Elige una categoría (define cuántos días antes hay que retirarlo).');
      return;
    }
    if (_fechaVencimiento == null) {
      setState(() => _error = 'Elige la fecha de vencimiento del lote.');
      return;
    }

    setState(() {
      _error = null;
      _guardando = true;
    });

    final categoria = _categorias.firstWhere((c) => c.id == _categoriaId);

    await _db.guardarProducto(ProductoInventario(sku: sku, nombre: nombre, imagenUrl: _imagenUrl, categoriaId: _categoriaId));
    final lote = await _db.guardarLote(sku: sku, fechaVencimiento: _fechaVencimiento!, cantidad: cantidad < 1 ? 1 : cantidad);

    final fechaAlerta = lote.fechaVencimiento.subtract(Duration(days: categoria.diasAnticipacion));
    await NotificationService.instancia.programarAvisoVencimiento(
      id: lote.id,
      nombreProducto: nombre,
      fecha: fechaAlerta,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    final formato = DateFormat('d MMM yyyy', 'es');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Guardado. Te avisamos el ${formato.format(fechaAlerta)}.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar producto')),
      body: _cargandoCategorias
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Identifica el producto',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escanea el código de barras del empaque, o escríbelo/escribe el '
                    'nombre y toca buscar. Si Farmatodo lo tiene, se autocompletan '
                    'nombre y foto -si no, los escribes tú-.',
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: AppColors.primary.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _skuController,
                          style: GoogleFonts.inter(fontSize: 15),
                          decoration: const InputDecoration(labelText: 'Código de barras / SKU'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _escanear,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        tooltip: 'Escanear',
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _buscandoEnFarmatodo ? null : _buscarEnFarmatodo,
                        icon: _buscandoEnFarmatodo
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        tooltip: 'Buscar en Farmatodo',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_imagenUrl != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(_imagenUrl!, width: 48, height: 48, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _nombreController,
                          style: GoogleFonts.inter(fontSize: 15),
                          decoration: const InputDecoration(labelText: 'Nombre del producto'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Categoría',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      TextButton.icon(
                        onPressed: _irACategorias,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Nueva'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Define cuántos días antes de vencer hay que retirarlo del anaquel.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.primary.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 10),
                  if (_categorias.isEmpty)
                    _AvisoSinCategorias(onCrear: _irACategorias)
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _categoriaId,
                      isExpanded: true,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.primary),
                      decoration: const InputDecoration(labelText: 'Elige una categoría'),
                      items: _categorias
                          .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.nombre} (${c.diasAnticipacion} días antes)')))
                          .toList(),
                      onChanged: (valor) => setState(() => _categoriaId = valor),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Vencimiento del lote',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _elegirFecha,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _fechaVencimiento == null
                                ? 'Elegir fecha de vencimiento'
                                : DateFormat('d MMM yyyy', 'es').format(_fechaVencimiento!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _cantidadController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 15),
                          decoration: const InputDecoration(labelText: 'Cant.'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.stockAgotado.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.stockAgotado.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.stockAgotado, height: 1.35),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Guardar y programar aviso'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AvisoSinCategorias extends StatelessWidget {
  const _AvisoSinCategorias({required this.onCrear});

  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    const colorAviso = Color(0xFFB45309);
    return InkWell(
      onTap: onCrear,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.category_outlined, color: colorAviso, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todavía no tienes categorías. Toca aquí para crear la primera (ej. "Chocolates", 30 días).',
                style: GoogleFonts.inter(fontSize: 12.5, color: colorAviso, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
