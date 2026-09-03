import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/search_provider.dart';
import '../services/server_config_service.dart';
import '../widgets/legal_footer.dart';
import 'result_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// Pantalla principal: buscador central de diseño limpio, punto de
/// entrada de la app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool? _servidorConfigurado;

  @override
  void initState() {
    super.initState();
    _revisarConfiguracion();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _revisarConfiguracion() async {
    final configurado = await ServerConfigService.instancia.estaConfigurado();
    if (!mounted) return;
    setState(() => _servidorConfigurado = configurado);
  }

  Future<void> _abrirAjustes() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _revisarConfiguracion();
  }

  void _buscar() {
    final consulta = _controller.text.trim();
    if (consulta.isEmpty) return;

    _focusNode.unfocus();
    context.read<SearchProvider>().buscar(consulta);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
  }

  Future<void> _abrirEscaner() async {
    _focusNode.unfocus();
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );

    if (codigo == null || codigo.isEmpty || !mounted) return;

    _controller.text = codigo;
    _buscar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Ajustes de conexión',
                icon: const Icon(Icons.settings_outlined, color: AppColors.primary),
                onPressed: _abrirAjustes,
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_servidorConfigurado == false) ...[
                        _AvisoConfigurarServidor(onTap: _abrirAjustes),
                        const SizedBox(height: 20),
                      ],
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.local_pharmacy_outlined,
                          color: AppColors.acento,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'FarmaTod',
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Consulta stock, información médica y alternativas '
                        'terapéuticas al instante. Tu inventario -vencimientos, '
                        'depósito y conteo- está en la pestaña Inventario.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.primary.withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 36),
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _buscar(),
                        style: GoogleFonts.inter(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Ej. Paracetamol, MED-0001, dolor de cabeza...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.primary,
                          ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          suffixIcon: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _controller,
                            builder: (context, value, _) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (value.text.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Limpiar búsqueda',
                                      icon: Icon(
                                        Icons.close,
                                        color: AppColors.primary.withValues(alpha: 0.4),
                                        size: 20,
                                      ),
                                      onPressed: () => _controller.clear(),
                                    ),
                                  IconButton(
                                    tooltip: 'Escanear código de barras',
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      color: AppColors.primary,
                                      size: 22,
                                    ),
                                    onPressed: _abrirEscaner,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _buscar,
                          icon: const Icon(Icons.search),
                          label: const Text('Buscar'),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'BÚSQUEDAS RÁPIDAS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: const [
                          'Paracetamol',
                          'Ibuprofeno',
                          'Loratadina',
                          'Omeprazol',
                        ].map((sugerencia) => _ChipSugerencia(
                              texto: sugerencia,
                              onTap: () {
                                _controller.text = sugerencia;
                              },
                            )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const LegalFooter(),
          ],
        ),
      ),
    );
  }
}

class _AvisoConfigurarServidor extends StatelessWidget {
  const _AvisoConfigurarServidor({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const colorAviso = Color(0xFFB45309);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.settings_suggest_outlined, color: colorAviso, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Configura la IP del servidor para empezar a buscar. Toca aquí.',
                style: GoogleFonts.inter(fontSize: 12.5, color: colorAviso, height: 1.35),
              ),
            ),
            const Icon(Icons.chevron_right, color: colorAviso, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ChipSugerencia extends StatelessWidget {
  const _ChipSugerencia({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          texto,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
