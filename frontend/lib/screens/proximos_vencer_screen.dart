import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/inventory_db_service.dart';
import '../services/notification_service.dart';
import '../widgets/product_card.dart';
import 'agregar_lote_screen.dart';

/// Lista de lotes registrados, ordenados por urgencia -según la fecha
/// de alerta calculada de cada uno (vencimiento real menos los días de
/// anticipación de su categoría)-, no por la fecha de vencimiento
/// cruda: así un producto con poca anticipación configurada puede
/// aparecer más urgente que uno que vence antes pero con más margen.
class ProximosAVencerScreen extends StatefulWidget {
  const ProximosAVencerScreen({super.key});

  @override
  State<ProximosAVencerScreen> createState() => _ProximosAVencerScreenState();
}

class _ProximosAVencerScreenState extends State<ProximosAVencerScreen> {
  final _db = InventoryDbService.instancia;
  List<LoteConDetalle> _lotes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final lotes = await _db.listarLotesConDetalle();
    lotes.sort((a, b) => a.fechaAlerta.compareTo(b.fechaAlerta));
    if (!mounted) return;
    setState(() {
      _lotes = lotes;
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
              child: _lotes.isEmpty
                  ? _EstadoVacio(onAgregar: _agregar)
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lotes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _TarjetaLote(
                          item: _lotes[i],
                          diasParaAlerta: _lotes[i].diasParaAlerta(ahora),
                          onRetirar: () => _retirar(_lotes[i]),
                        ),
                      ),
                    ),
            ),
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
                    '${item.categoria?.nombre ?? 'Sin categoría'} · Vence ${formato.format(item.lote.fechaVencimiento)}'
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
