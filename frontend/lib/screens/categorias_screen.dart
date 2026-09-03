import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/inventory_db_service.dart';

/// Administra los tipos de producto y cuántos días antes de la fecha
/// de vencimiento real hay que retirarlos del anaquel -cada tipo tiene
/// el suyo (ej. "Chocolates" 30 días, "Champú" 60 días)-. Es la base
/// que usa "Agregar producto" para calcular cuándo avisar.
class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  final _db = InventoryDbService.instancia;
  List<CategoriaVencimiento> _categorias = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final categorias = await _db.listarCategorias();
    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      _cargando = false;
    });
  }

  Future<void> _abrirFormulario({CategoriaVencimiento? categoria}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioCategoria(categoria: categoria),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _borrar(CategoriaVencimiento categoria) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar categoría?'),
        content: Text('Los productos con "${categoria.nombre}" se quedan sin categoría asignada.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmar == true) {
      await _db.borrarCategoria(categoria.id);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías de vencimiento')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppColors.acento,
        foregroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: _categorias.isEmpty
                  ? _EstadoVacio(onCrear: () => _abrirFormulario())
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _categorias.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final categoria = _categorias[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.category_outlined, color: AppColors.acento, size: 18),
                            ),
                            title: Text(
                              categoria.nombre,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                            subtitle: Text(
                              'Retirar ${categoria.diasAnticipacion} días antes de vencer',
                              style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.primary.withValues(alpha: 0.6)),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _abrirFormulario(categoria: categoria),
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                ),
                                IconButton(
                                  onPressed: () => _borrar(categoria),
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  color: AppColors.stockAgotado,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.onCrear});

  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined, size: 48, color: AppColors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Sin categorías todavía',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Ej. "Chocolates" con 30 días de anticipación, "Champú" con 60. '
              'Cada tipo de producto tiene su propio tiempo antes de vencer.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppColors.primary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onCrear,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear categoría'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormularioCategoria extends StatefulWidget {
  const _FormularioCategoria({this.categoria});

  final CategoriaVencimiento? categoria;

  @override
  State<_FormularioCategoria> createState() => _FormularioCategoriaState();
}

class _FormularioCategoriaState extends State<_FormularioCategoria> {
  late final _nombreController = TextEditingController(text: widget.categoria?.nombre ?? '');
  late final _diasController = TextEditingController(text: widget.categoria?.diasAnticipacion.toString() ?? '');
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _diasController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreController.text.trim();
    final dias = int.tryParse(_diasController.text.trim());

    if (nombre.isEmpty || dias == null || dias < 0) {
      setState(() => _error = 'Escribe un nombre y un número de días válido (0 o más).');
      return;
    }

    setState(() {
      _error = null;
      _guardando = true;
    });

    await InventoryDbService.instancia.guardarCategoria(id: widget.categoria?.id, nombre: nombre, diasAnticipacion: dias);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.categoria == null ? 'Nueva categoría' : 'Editar categoría',
              style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreController,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 15),
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Chocolates'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _diasController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(fontSize: 15),
              decoration: const InputDecoration(
                labelText: 'Días de anticipación',
                hintText: 'Ej. 30',
                suffixText: 'días antes de vencer',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.stockAgotado)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
