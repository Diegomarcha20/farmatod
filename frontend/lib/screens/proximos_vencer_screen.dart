import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/inventory_db_service.dart';
import '../services/notification_service.dart';
import '../widgets/product_card.dart';
import 'agregar_lote_screen.dart';

/// Lista de lotes registrados, agrupada por categoría (tipo de
/// producto) para que sea fácil de recorrer -dentro de cada categoría,
/// ordenados por urgencia según la fecha de alerta calculada (fecha de
/// vencimiento real menos los días de anticipación de esa categoría),
/// no por la fecha de vencimiento cruda: así un producto con poca
/// anticipación configurada puede aparecer más urgente que uno que
/// vence antes pero con más margen-. Las categorías mismas se ordenan
/// por su producto más urgente, para que la sección que más apura
/// quede arriba.
class ProximosAVencerScreen extends StatefulWidget {
  const ProximosAVencerScreen({super.key});

  @override
  State<ProximosAVencerScreen> createState() => _ProximosAVencerScreenState();
}

class _GrupoCategoria {
  _GrupoCategoria(this.nombre) : items = [];

  final String nombre;
  final List<LoteConDetalle> items;
}

class _ProximosAVencerScreenState extends State<ProximosAVencerScreen> {
  final _db = InventoryDbService.instancia;
  List<_GrupoCategoria> _grupos = [];
  int _totalLotes = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final lotes = await _db.listarLotesConDetalle();

    final porCategoria = <String, _GrupoCategoria>{};
    for (final lote in lotes) {
      final nombre = lote.categoria?.nombre ?? 'Sin categoría';
      porCategoria.putIfAbsent(nombre, () => _GrupoCategoria(nombre)).items.add(lote);
    }
    for (final grupo in porCategoria.values) {
      grupo.items.sort((a, b) => a.fechaAlerta.compareTo(b.fechaAlerta));
    }
    final grupos = porCategoria.values.toList()
      ..sort((a, b) => a.items.first.fechaAlerta.compareTo(b.items.first.fechaAlerta));

    if (!mounted) return;
    setState(() {
      _grupos = grupos;
      _totalLotes = lotes.length;
      _cargando = false;
    });
  }

  Future<void> _retirar(LoteConDetalle item) async {
    await NotificationService.instancia.cancelarAviso(item.lote.id);
    await _db.borrarLote(item.lote.id);
    _cargar();
  }

  Future<void> _agregar() async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AgregarLoteScreen()),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Próximos a vencer')),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregar,
        backgroundColor: AppColors.acento,
        foregroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: _totalLotes == 0
                  ? _EstadoVacio(onAgregar: _agregar)
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _grupos.length,
                        itemBuilder: (context, i) {
                          final grupo = _grupos[i];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (i > 0) const SizedBox(height: 18),
                              _EncabezadoCategoria(nombre: grupo.nombre, cantidad: grupo.items.length),
                              const SizedBox(height: 10),
                              ...grupo.items.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _TarjetaLote(
                                    item: item,
                                    diasParaAlerta: item.diasParaAlerta(ahora),
                                    onRetirar: () => _retirar(item),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
    );
  }
}

class _EncabezadoCategoria extends StatelessWidget {
  const _EncabezadoCategoria({required this.nombre, required this.cantidad});

  final String nombre;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.category_outlined, size: 15, color: AppColors.primary.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        Text(
          nombre.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.primary.withValues(alpha: 0.6)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Text(
            '$cantidad',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}

class _TarjetaLote extends StatelessWidget {
  const _TarjetaLote({required this.item, required this.diasParaAlerta, required this.onRetirar});

  final LoteConDetalle item;
  final int diasParaAlerta;
  final VoidCallback onRetirar;

  @override
  Widget build(BuildContext context) {
    final vencido = diasParaAlerta <= 0;
    final color = vencido
        ? AppColors.stockAgotado
        : diasParaAlerta <= 7
            ? const Color(0xFFB45309)
            : AppColors.stockDisponible;
    final texto = vencido
        ? (diasParaAlerta == 0 ? 'Retirar hoy' : 'Atrasado ${-diasParaAlerta} días')
        : 'Faltan $diasParaAlerta días';
    final formato = DateFormat('d MMM yyyy', 'es');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductoImagen(url: item.producto.imagenUrl, tamano: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.producto.nombre,
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vence ${formato.format(item.lote.fechaVencimiento)}'
                    '${item.lote.cantidad > 1 ? ' · x${item.lote.cantidad}' : ''}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      texto,
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRetirar,
              icon: const Icon(Icons.check_circle_outline),
              color: AppColors.primary.withValues(alpha: 0.4),
              tooltip: 'Ya lo retiré del anaquel',
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.onAgregar});

  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined, size: 48, color: AppColors.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              'Nada en seguimiento todavía',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un producto con su fecha de vencimiento para que te avisemos '
              'a tiempo de retirarlo del anaquel.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AppColors.primary.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: onAgregar, icon: const Icon(Icons.add_rounded), label: const Text('Agregar producto')),
          ],
        ),
      ),
    );
  }
}
