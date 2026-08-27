import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';

/// Pantalla de cámara para escanear el código de barras del empaque
/// físico del medicamento. Al detectar el primer código válido, cierra
/// la pantalla devolviendo el valor escaneado (`Navigator.pop`) para
/// que quien la abrió dispare la búsqueda automáticamente.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );

  bool _yaCapturado = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _alDetectar(BarcodeCapture captura) {
    if (_yaCapturado) return;

    final codigos = captura.barcodes;
    if (codigos.isEmpty) return;

    final valor = codigos.first.rawValue;
    if (valor == null || valor.trim().isEmpty) return;

    _yaCapturado = true;
    Navigator.of(context).pop(valor.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código de barras'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              final encendido = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(encendido ? Icons.flash_on : Icons.flash_off),
                tooltip: 'Linterna',
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _alDetectar),
          _MarcoDeEscaneo(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Apunta al código de barras del empaque',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarcoDeEscaneo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 280,
        height: 160,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.acento, width: 3),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
