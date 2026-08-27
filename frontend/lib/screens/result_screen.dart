import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/producto.dart';
import '../providers/search_provider.dart';
import '../services/local_cache_service.dart';
import '../widgets/legal_footer.dart';
import '../widgets/product_card.dart';

/// Pantalla de resultado: integra la ficha médica (IA/base local), el
/// SKU y la ubicación en el planograma, la disponibilidad obtenida por
/// scraping en la sucursal, y -si no hay stock- las alternativas
/// terapéuticas con el mismo principio activo.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<SearchProvider>(
          builder: (context, provider, _) => Text(
            provider.consultaActual.isEmpty
                ? 'Resultado'
                : '"${provider.consultaActual}"',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Consumer<SearchProvider>(
                builder: (context, provider, _) {
                  switch (provider.status) {
                    case SearchStatus.loading:
                      return const _CargandoView();
                    case SearchStatus.error:
                      return _ErrorView(
                        mensaje: provider.errorMessage ??
                            'Ocurrió un error inesperado.',
                        onReintentar: provider.reintentar,
                      );
                    case SearchStatus.success:
                      final data = provider.resultado;
                      if (data == null) return const _CargandoView();
                      return data.encontrado
                          ? _ResultadoEncontrado(data: data)
                          : _NoEncontradoView(mensaje: data.mensaje);
                    case SearchStatus.offline:
                      final cacheado = provider.productoOffline;
                      if (cacheado == null) return const _CargandoView();
                      return _ResultadoOffline(cacheado: cacheado);
                    case SearchStatus.idle:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ),
            const LegalFooter(),
          ],
        ),
      ),
    );
  }
}

class _CargandoView extends StatelessWidget {
  const _CargandoView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.acento),
          const SizedBox(height: 16),
          Text(
            'Consultando stock y alternativas...',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.stockAgotado.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.stockAgotado,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No se pudo completar la búsqueda',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: AppColors.primary.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoEncontradoView extends StatelessWidget {
  const _NoEncontradoView({this.mensaje});

  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                color: AppColors.primary.withValues(alpha: 0.5),
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin coincidencias',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mensaje ??
                  'No encontramos el medicamento ni alternativas por '
                      'principio activo para esta búsqueda.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: AppColors.primary.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoEncontrado extends StatelessWidget {
  const _ResultadoEncontrado({required this.data});

  final BuscarResponse data;

  @override
  Widget build(BuildContext context) {
    final producto = data.producto!;
    final hayStock = data.stockEfectivo > 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _FichaMedicaCard(producto: producto, data: data),
        const SizedBox(height: 14),
        _SkuUbicacionCard(producto: producto),
        const SizedBox(height: 14),
        if (data.infoSucursal != null)
          _SucursalCard(info: data.infoSucursal!, producto: producto),
        if (!hayStock) ...[
          const SizedBox(height: 26),
          Row(
            children: [
              Icon(Icons.sync_alt_rounded, size: 18, color: AppColors.primary.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'Alternativas con el mismo principio activo',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (data.alternativas.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'No hay alternativas con stock disponible en este momento '
                'para el mismo principio activo.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.primary.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ...data.alternativas.map(
              (alternativa) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ProductCard(producto: alternativa),
              ),
            ),
        ],
      ],
    );
  }
}

/// Resultado servido desde el caché local (SQLite) cuando no hay
/// conexión con el backend. Muestra SKU y ubicación en el planograma
/// -lo único que sigue siendo confiable sin red-, y reemplaza la
/// sección de IA/disponibilidad en vivo por un aviso claro en vez de
/// simular datos que podrían estar desactualizados.
class _ResultadoOffline extends StatelessWidget {
  const _ResultadoOffline({required this.cacheado});

  final ProductoCacheado cacheado;

  @override
  Widget build(BuildContext context) {
    final producto = cacheado.producto;

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _AvisoSinConexion(guardadoEn: cacheado.guardadoEn),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductoImagen(url: producto.imagenUrl, tamano: 72),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        producto.nombre,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Etiqueta(texto: producto.principioActivo, icono: Icons.science_outlined),
                    if (producto.categoria != null)
                      _Etiqueta(texto: producto.categoria!, icono: Icons.category_outlined),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '\$${producto.precio.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'Último stock registrado: ${producto.stock} uds. (no en tiempo real)',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.primary.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SkuUbicacionCard(producto: producto),
      ],
    );
  }
}

class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion({required this.guardadoEn});

  final DateTime guardadoEn;

  String get _tiempoTranscurrido {
    final minutos = DateTime.now().difference(guardadoEn).inMinutes;
    if (minutos < 1) return 'hace instantes';
    if (minutos < 60) return 'hace $minutos min';
    final horas = minutos ~/ 60;
    if (horas < 24) return 'hace $horas h';
    final dias = horas ~/ 24;
    return 'hace $dias d';
  }

  @override
  Widget build(BuildContext context) {
    const colorAviso = Color(0xFFB45309); // ámbar, tono "degradado pero útil"
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded, color: colorAviso, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sin conexión externa',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colorAviso,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mostrando el último dato guardado en este dispositivo '
                  '($_tiempoTranscurrido). La disponibilidad en vivo y la '
                  'ficha de IA no están disponibles sin conexión.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: colorAviso.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ficha Médica": combina lo que sabe la base local con lo detectado
/// por IA (principio activo, categoría terapéutica y descripción).
class _FichaMedicaCard extends StatelessWidget {
  const _FichaMedicaCard({required this.producto, required this.data});

  final Producto producto;
  final BuscarResponse data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: AppColors.acento,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ficha médica',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (data.esDetectadoPorIA)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.acento.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Sugerido por IA',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductoImagen(url: producto.imagenUrl, tamano: 88),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        producto.nombre,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      if (producto.imagenReferencial) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Foto de referencia (catálogo de Farmatodo)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Etiqueta(texto: producto.principioActivo, icono: Icons.science_outlined),
                if (producto.categoria != null)
                  _Etiqueta(texto: producto.categoria!, icono: Icons.category_outlined),
                StockBadge(stock: producto.stock),
              ],
            ),
            if (producto.descripcion != null) ...[
              const SizedBox(height: 14),
              Text(
                producto.descripcion!,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.primary.withValues(alpha: 0.75),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '\$${producto.precio.toStringAsFixed(2)}',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.icono});

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.fondo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: AppColors.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// SKU y ubicación exacta en el planograma de la sucursal.
class _SkuUbicacionCard extends StatelessWidget {
  const _SkuUbicacionCard({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _DatoUbicacion(
                icono: Icons.qr_code_2_rounded,
                etiqueta: 'CÓDIGO SKU',
                valor: producto.sku,
              ),
            ),
            Container(width: 1, height: 40, color: const Color(0xFFE2E8F0)),
            const SizedBox(width: 16),
            Expanded(
              child: _DatoUbicacion(
                icono: Icons.place_outlined,
                etiqueta: 'UBICACIÓN EN PLANOGRAMA',
                valor: producto.ubicacionPlanograma,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatoUbicacion extends StatelessWidget {
  const _DatoUbicacion({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 13, color: AppColors.acento),
            const SizedBox(width: 5),
            Text(
              etiqueta,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          valor,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

/// Disponibilidad obtenida por scraping en la sucursal (imagen,
/// cantidad y si la fuente fue real o simulada por caída del sitio).
class _SucursalCard extends StatelessWidget {
  const _SucursalCard({required this.info, required this.producto});

  final InfoSucursal info;
  final Producto producto;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 56,
                height: 56,
                color: AppColors.fondo,
                child: info.imagenUrl == null
                    ? Icon(Icons.storefront_outlined, color: AppColors.primary.withValues(alpha: 0.35))
                    : Image.network(
                        info.imagenUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.storefront_outlined,
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          info.sucursal,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (info.fuente == 'simulado')
                        Tooltip(
                          message: 'Sitio de la sucursal no disponible; '
                              'se muestra un estimado de referencia.',
                          child: Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Disponibilidad en sucursal (web)',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  StockBadge(stock: info.disponible ? info.cantidad : 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
