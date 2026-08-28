import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/producto.dart';

/// Badge de disponibilidad: verde (#10B981) si hay stock, rojo
/// (#EF4444) si está agotado. Farmatodo no da una cantidad exacta, así
/// que se muestra la "cantidad aproximada" que sí reporta ("Disponible",
/// "Pocas unidades", etc.) en vez de un número inventado. Reutilizado
/// en la tarjeta de producto y en la ficha médica del resultado.
class StockBadge extends StatelessWidget {
  const StockBadge({
    super.key,
    required this.enStock,
    this.cantidadAproximada,
    this.compacto = false,
  });

  final bool enStock;
  final String? cantidadAproximada;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final color = enStock ? AppColors.stockDisponible : AppColors.stockAgotado;
    final texto = compacto
        ? (enStock ? 'En stock' : 'Agotado')
        : (cantidadAproximada?.isNotEmpty == true
            ? cantidadAproximada!
            : (enStock ? 'En stock' : 'Agotado'));

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

/// Tarjeta reutilizable para mostrar un producto (resultado principal,
/// opción entre varias coincidencias, o alternativa terapéutica):
/// bordes de 16px, elevación 2 y badge de stock verde/rojo, según la
/// paleta corporativa.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.producto, this.onTap});

  final Producto producto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitulo = [
      if (producto.principioActivo != null) producto.principioActivo!,
      if (producto.laboratorio != null) producto.laboratorio!,
    ].join(' · ');

    // Muestra una sola divisa de referencia en la tarjeta compacta
    // (USD si está configurada, si no la primera que haya) -la ficha
    // completa del resultado sí muestra todas-.
    final codigosDivisa = producto.precios.keys.toList();
    final codigoReferencia = codigosDivisa.contains('USD') ? 'USD' : (codigosDivisa.isNotEmpty ? codigosDivisa.first : null);
    final divisaReferencia = codigoReferencia != null ? producto.precios[codigoReferencia] : null;

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
                    if (subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: AppColors.primary.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                    if (producto.ubicacionPlanograma != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: AppColors.primary.withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              producto.ubicacionPlanograma!,
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
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bs. ${producto.precioBs.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            if (divisaReferencia != null)
                              Text(
                                '≈ ${divisaReferencia.totalConIgtf.toStringAsFixed(2)} $codigoReferencia',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                        StockBadge(enStock: producto.enStock, compacto: true),
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
