import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/inventario.dart';
import '../services/api_service.dart';
import '../services/inventory_db_service.dart';
import '../widgets/product_card.dart';
import 'scanner_screen.dart';

/// Lo que falta en el anaquel, resuelto contra el depósito propio: se
/// escanea (o busca) cada producto que falta y la pantalla dice de una
/// si hay existencias registradas en depósito para ir a reponerlo -o
/// si hace falta registrar cuánto hay-. "Depósito" es la trastienda de
/// la propia tienda, un dato que el usuario mantiene aquí -Farmatodo no
/// expone stock de trastienda/depósito en su catálogo público-.
class DepositoScreen extends StatefulWidget {
  const DepositoScreen({super.key});

  @override
  State<DepositoScreen> createState() => _DepositoScreenState();
}

class _DepositoScreenState extends State<DepositoScreen> {
  final _api = ApiService();
  final _db = InventoryDbService.instancia;
  final _busquedaController = TextEditingController();

  final List<_ResultadoFaltante> _faltantes = [];
  bool _buscando = false;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
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

      final registrado = await _db.obtenerProducto(encontrado.sku);
      if (!mounted) return;
      setState(() {
        _faltantes.removeWhere((f) => f.sku == encontrado.sku);
        _faltantes.insert(
          0,
          _ResultadoFaltante(
            sku: encontrado.sku,
            nombre: encontrado.nombre,
            imagenUrl: encontrado.imagenUrl,
            cantidadDeposito: registrado?.cantidadDeposito,
          ),
        );
      });
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

  Future<void> _registrarStock(_ResultadoFaltante item) async {
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

    if (!mounted) return;
    setState(() {
      final i = _faltantes.indexWhere((f) => f.sku == item.sku);
      if (i != -1) _faltantes[i] = item.copyWith(cantidadDeposito: cantidad);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Faltantes y depósito')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escanea o busca lo que falta en el anaquel',
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Te decimos al instante si según tu depósito tienes existencias para reponer.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.primary.withValues(alpha: 0.6)),
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
                        onPressed: _escanear,
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
                          'Los productos que vayas escaneando aparecen aquí, con su estado en el depósito.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.primary.withValues(alpha: 0.5)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _faltantes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _TarjetaFaltante(
                        item: _faltantes[i],
                        onRegistrar: () => _registrarStock(_faltantes[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoFaltante {
  const _ResultadoFaltante({required this.sku, required this.nombre, this.imagenUrl, this.cantidadDeposito});

  final String sku;
  final String nombre;
  final String? imagenUrl;
  final int? cantidadDeposito;

  _ResultadoFaltante copyWith({int? cantidadDeposito}) {
    return _ResultadoFaltante(sku: sku, nombre: nombre, imagenUrl: imagenUrl, cantidadDeposito: cantidadDeposito);
  }
}

class _TarjetaFaltante extends StatelessWidget {
  const _TarjetaFaltante({required this.item, required this.onRegistrar});

  final _ResultadoFaltante item;
  final VoidCallback onRegistrar;

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
        child: Row(
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
            TextButton(onPressed: onRegistrar, child: const Text('Actualizar')),
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
