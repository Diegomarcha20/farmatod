import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/server_config_service.dart';

/// Pantalla de Ajustes: configura la dirección del backend (y, si el
/// backend la exige, el código de acceso). Es lo primero que hay que
/// llenar al instalar la app en un teléfono real, ya que -a diferencia
/// del emulador- no hay forma de adivinar dónde vive el servidor.
///
/// El mismo campo de URL sirve para los dos escenarios posibles:
/// - Backend en la Wi-Fi de la tienda: `http://192.168.1.42:8000`.
/// - Backend desplegado en internet: `https://tu-app.onrender.com`.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _config = ServerConfigService.instancia;
  final _urlController = TextEditingController();
  final _codigoController = TextEditingController();

  bool _cargando = true;
  bool _probando = false;
  bool _guardando = false;
  PruebaConexion? _resultadoPrueba;

  @override
  void initState() {
    super.initState();
    _cargarValoresActuales();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _cargarValoresActuales() async {
    final url = await _config.obtenerUrlBase();
    final codigo = await _config.obtenerCodigoAcceso();
    if (!mounted) return;
    setState(() {
      _urlController.text = url ?? '';
      _codigoController.text = codigo ?? '';
      _cargando = false;
    });
  }

  Future<void> _probarConexion() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() {
        _resultadoPrueba = const PruebaConexion(
          ok: false,
          mensaje: 'Escribe la dirección del servidor primero.',
        );
      });
      return;
    }

    setState(() {
      _probando = true;
      _resultadoPrueba = null;
    });

    final resultado = await _config.probarConexion(
      url: _urlController.text,
      codigoAcceso: _codigoController.text,
    );

    if (!mounted) return;
    setState(() {
      _probando = false;
      _resultadoPrueba = resultado;
    });
  }

  Future<void> _guardar() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _resultadoPrueba = const PruebaConexion(
          ok: false,
          mensaje: 'Escribe la dirección del servidor.',
        );
      });
      return;
    }

    setState(() => _guardando = true);
    await _config.guardar(url: url, codigoAcceso: _codigoController.text);
    if (!mounted) return;
    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración guardada.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes de conexión')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColors.acento))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Servidor del backend',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Si el backend corre en una PC de la tienda: la IP de esa PC '
                    'y el puerto (la ves con "ipconfig" en esa PC), por ejemplo '
                    'http://192.168.1.42:8000.\n\n'
                    'Si el backend está desplegado en internet (Render, etc.): '
                    'pega la URL que te dio el proveedor, por ejemplo '
                    'https://tu-app.onrender.com.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    style: GoogleFonts.inter(fontSize: 15),
                    decoration: const InputDecoration(
                      labelText: 'Dirección del servidor',
                      hintText: '192.168.1.42:8000 o https://tu-app.onrender.com',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codigoController,
                    obscureText: true,
                    style: GoogleFonts.inter(fontSize: 15),
                    decoration: const InputDecoration(
                      labelText: 'Código de acceso (opcional)',
                      hintText: 'Solo si el backend lo exige',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Déjalo vacío si tu backend corre en la Wi-Fi de la tienda sin '
                    'código configurado. Rellénalo solo si desplegaste el backend '
                    'en internet con APP_ACCESS_KEY definida.',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.primary.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_resultadoPrueba != null) ...[
                    _AvisoPrueba(resultado: _resultadoPrueba!),
                    const SizedBox(height: 14),
                  ],
                  OutlinedButton.icon(
                    onPressed: _probando ? null : _probarConexion,
                    icon: _probando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded),
                    label: Text(_probando ? 'Probando... (puede tardar si el servidor está dormido)' : 'Probar conexión'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AvisoPrueba extends StatelessWidget {
  const _AvisoPrueba({required this.resultado});

  final PruebaConexion resultado;

  @override
  Widget build(BuildContext context) {
    final color = resultado.ok ? AppColors.stockDisponible : AppColors.stockAgotado;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            resultado.ok ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              resultado.mensaje,
              style: GoogleFonts.inter(fontSize: 13, color: color, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
