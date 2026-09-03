import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/api_service.dart';
import '../services/inventory_db_service.dart';
import '../widgets/product_card.dart';
import 'scanner_screen.dart';

/// Lo que falta en el anaquel, resuelto contra el depósito propio: se
/// recorre el planograma escaneando (o buscando) cada producto que
/// falta, y la pantalla dice de una si hay existencias registradas en
/// depósito para ir a reponerlo -o si hace falta registrar cuánto hay-.
///
/// La lista de faltantes QUEDA GUARDADA -sobrevive a salir de la
/// pantalla, cerrar la app, etc.-: cada producto se queda ahí hasta
/// que el usuario lo marca como "ya lo surtí" después de reponerlo en
/// el anaquel. No es una lista de la sesión actual, es la lista de
/// pendientes por surtir.
///
/// "Depósito" es la trastienda de la propia tienda, un dato que el
/// usuario mantiene aquí -Farmatodo no expone stock de trastienda/
/// depósito en su catálogo público-.
class DepositoScreen extends StatefulWidget {
  const DepositoScreen({super.key});

  @override
  State<DepositoScreen> createState() => _DepositoScreenState();
}

class _DepositoScreenState extends State<DepositoScreen> {
  final _api = ApiService();
  final _db = InventoryDbService.instancia;
  final _busquedaController = TextEditingController();

  List<FaltantePendiente> _faltantes = [];
  bool _cargando = true;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final faltantes = await _db.listarFaltantesConDeposito();
    if (!mounted) return;
    setState(() {
      _faltantes = faltantes;
      _cargando = false;
    });
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (codigo == null || codigo.isEmpty || !mounted) return;
    await _resolver(codigo);
  }

  Future<void> _buscarPorTexto() async {
    final termino = _busquedaController.text.trim();
    if (termino.isEmpty) return;
    await _resolver(termino);
    _busquedaController.clear();
  }

  Future<void> _resolver(String termino) async {
    setState(() => _buscando = true);
    try {
      final resultado = await _api.buscar(termino);
      final encontrado = resultado.producto ?? (resultado.opciones.isNotEmpty ? resultado.opciones.first : null);

      if (encontrado == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró ese producto en Farmatodo.')),
          );
        }
        return;
      }

      await _db.agregarFaltante(encontrado.sku, encontrado.nombre, encontrado.imagenUrl);
      await _cargar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo consultar Farmatodo en este momento.')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _registrarStock(FaltantePendiente item) async {
    final cantidad = await showDialog<int>(
      context: context,
      builder: (context) => _DialogoCantidad(valorInicial: item.cantidadDeposito ?? 0),
    );
    if (cantidad == null) return;

    final existente = await _db.obtenerProducto(item.sku);
    await _db.guardarProducto(
      (existente ?? ProductoInventario(sku: item.sku, nombre: item.nombre, imagenUrl: item.imagenUrl)).copyWith(
        cantidadDeposito: cantidad,
        nombre: item.nombre,
        imagenUrl: item.imagenUrl,
      ),
    );
    await _cargar();
  }

  Future<void> _marcarSurtido(FaltantePendiente item) async {
    await _db.quitarFaltante(item.sku);
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.nombre}: marcado como surtido.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Faltantes y depósito'),
        actions: [
          if (_faltantes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_faltantes.length} pendientes',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recorre el planograma y escanea lo que falta',
                          style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Se va guardando en tu lista de pendientes -queda ahí hasta que marques '
                          '"ya lo surtí" después de reponerlo en el anaquel-.',
                          style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: AppColors.primary.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _busquedaController,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => _buscarPorTexto(),
                                style: GoogleFonts.inter(fontSize: 14),
                                decoration: const InputDecoration(hintText: 'Nombre o código...'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _buscando ? null : _escanear,
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              tooltip: 'Escanear',
                            ),
                            IconButton(
                              onPressed: _buscando ? null : _buscarPorTexto,
                              icon: _buscando
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.search),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _faltantes.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Sin pendientes por surtir. Los productos que escanees aparecen aquí, '
                                'con su estado en el depósito, y se quedan hasta que los marques como surtidos.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary.withValues(alpha: 0.5)),
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _cargar,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: _faltantes.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _TarjetaFaltante(
                                item: _faltantes[i],
                                onRegistrar: () => _registrarStock(_faltantes[i]),
                                onSurtido: () => _marcarSurtido(_faltantes[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TarjetaFaltante extends StatelessWidget {
  const _TarjetaFaltante({required this.item, required this.onRegistrar, required this.onSurtido});

  final FaltantePendiente item;
  final VoidCallback onRegistrar;
  final VoidCallback onSurtido;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String texto;
    if (item.cantidadDeposito == null) {
      color = AppColors.primary.withValues(alpha: 0.5);
      texto = 'No registrado en depósito';
    } else if (item.cantidadDeposito! > 0) {
      color = AppColors.stockDisponible;
      texto = 'Sí hay: ${item.cantidadDeposito} en depósito';
    } else {
      color = AppColors.stockAgotado;
      texto = 'No hay en depósito';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProductoImagen(url: item.imagenUrl, tamano: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nombre,
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(texto, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Wrap en vez de Row: en pantallas angostas, estos dos
            // botones combinados pueden no caber en una sola línea -así
            // pasan a la siguiente en vez de desbordar-.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton(onPressed: onRegistrar, child: const Text('Actualizar depósito')),
                TextButton.icon(
                  onPressed: onSurtido,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Ya lo surtí'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoCantidad extends StatefulWidget {
  const _DialogoCantidad({required this.valorInicial});

  final int valorInicial;

  @override
  State<_DialogoCantidad> createState() => _DialogoCantidadState();
}

class _DialogoCantidadState extends State<_DialogoCantidad> {
  late final _controller = TextEditingController(text: widget.valorInicial.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Existencias en depósito'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Cantidad actual'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(int.tryParse(_controller.text.trim()) ?? 0),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
