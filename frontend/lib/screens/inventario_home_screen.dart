import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import 'categorias_screen.dart';
import 'conteo_screen.dart';
import 'deposito_screen.dart';
import 'proximos_vencer_screen.dart';

/// Centro de inventario propio de la tienda: vencimientos, depósito/
/// faltantes y conteo físico -todo lo que no sale del catálogo de
/// Farmatodo, sino que la propia tienda alimenta y mantiene-.
class InventarioHomeScreen extends StatelessWidget {
  const InventarioHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Inventario',
            style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(
            'Vencimientos, depósito y conteo -tuyo, no del catálogo de Farmatodo-.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),
          _TarjetaModulo(
            icono: Icons.event_busy_outlined,
            titulo: 'Próximos a vencer',
            descripcion: 'Productos por retirar del anaquel, según el tiempo de cada categoría.',
            color: const Color(0xFFB45309),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProximosAVencerScreen())),
          ),
          const SizedBox(height: 14),
          _TarjetaModulo(
            icono: Icons.category_outlined,
            titulo: 'Categorías de vencimiento',
            descripcion: 'Configura cada tipo de producto y sus días de anticipación.',
            color: AppColors.primary,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriasScreen())),
          ),
          const SizedBox(height: 14),
          _TarjetaModulo(
            icono: Icons.inventory_2_outlined,
            titulo: 'Faltantes y depósito',
            descripcion: 'Escanea lo que falta en el anaquel y revisa si hay en depósito para reponer.',
            color: AppColors.stockDisponible,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepositoScreen())),
          ),
          const SizedBox(height: 14),
          _TarjetaModulo(
            icono: Icons.qr_code_scanner_rounded,
            titulo: 'Conteo',
            descripcion: 'Escanea cada producto contado; suma automática, sin errores de tecleo.',
            color: AppColors.acento,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConteoScreen())),
          ),
        ],
      ),
    );
  }
}

class _TarjetaModulo extends StatelessWidget {
  const _TarjetaModulo({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descripcion,
                      style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: AppColors.primary.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.primary.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
