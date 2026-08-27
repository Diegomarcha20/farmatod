import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/producto.dart';

/// Badge de disponibilidad: verde (#10B981) si hay stock, rojo
/// (#EF4444) si está agotado. Reutilizado en la tarjeta de producto y
/// en la ficha médica del resultado.
class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.stock, this.compacto = false});

  final int stock;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final disponible = stock > 0;
    final color = disponible ? AppColors.stockDisponible : AppColors.stockAgotado;
    final texto = disponible
        ? (compacto ? 'En stock' : 'En stock · $stock uds.')
        : 'Agotado';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta reutilizable para mostrar un producto (resultado principal
/// o alternativa terapéutica): bordes de 16px, elevación 2 y badge de
/// stock verde/rojo, según la paleta corporativa.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.producto, this.onTap});

  final Producto producto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductoImagen(url: producto.imagenUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      producto.laboratorio != null
                          ? '${producto.principioActivo} · ${producto.laboratorio}'
                          : producto.principioActivo,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppColors.primary.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.qr_code_2, size: 14, color: AppColors.primary.withValues(alpha: 0.45)),
                        const SizedBox(width: 4),
                        Text(
                          producto.sku,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.primary.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 14, color: AppColors.primary.withValues(alpha: 0.45)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            producto.ubicacionPlanograma,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.primary.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '\$${producto.precio.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        StockBadge(stock: producto.stock, compacto: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foto de producto reutilizable (tarjetas de alternativas y ficha
/// médica principal): placeholder mientras carga, ícono neutro si no
/// hay URL o si la carga falla -nunca un hueco en blanco ni un error
/// visible-.
class ProductoImagen extends StatelessWidget {
  const ProductoImagen({super.key, required this.url, this.tamano = 64});

  final String? url;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: tamano,
        height: tamano,
        color: AppColors.fondo,
        child: url == null
            ? _icono()
            : Image.network(
                url!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: SizedBox(
                      width: tamano * 0.28,
                      height: tamano * 0.28,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => _icono(),
              ),
      ),
    );
  }

  Widget _icono() {
    return Center(
      child: Icon(
        Icons.medication_outlined,
        color: AppColors.primary.withValues(alpha: 0.35),
        size: tamano * 0.44,
      ),
    );
  }
}
