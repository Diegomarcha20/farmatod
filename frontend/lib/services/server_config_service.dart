import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Dirección del backend + código de acceso opcional, persistidos en
/// el dispositivo (SharedPreferences).
///
/// Admite dos modos, con el mismo campo de texto:
/// - Backend en la Wi-Fi de la tienda: `http://192.168.1.42:8000`.
/// - Backend desplegado en internet (Render, etc.): `https://tu-app.onrender.com`.
///
/// En un teléfono físico real, `10.0.2.2` (solo válido en el emulador
/// Android) y `127.0.0.1` (apuntaría al propio teléfono) NUNCA
/// funcionan como valor por defecto -por eso siempre hay que
/// configurar la URL real en Ajustes-.
class ServerConfigService {
  ServerConfigService._interno();

  static final ServerConfigService instancia = ServerConfigService._interno();

  static const _claveUrl = 'servidor_url';
  static const _claveCodigoAcceso = 'servidor_codigo_acceso';
  static const puertoPorDefecto = 8000;

  String _normalizarUrl(String entrada) {
    var url = entrada.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  Future<String?> obtenerUrlBase() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_claveUrl);
    return (url == null || url.trim().isEmpty) ? null : url.trim();
  }

  Future<String?> obtenerCodigoAcceso() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getString(_claveCodigoAcceso);
    return (codigo == null || codigo.trim().isEmpty) ? null : codigo.trim();
  }

  Future<bool> estaConfigurado() async => (await obtenerUrlBase()) != null;

  Future<void> guardar({required String url, String? codigoAcceso}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrl, _normalizarUrl(url));
    await prefs.setString(_claveCodigoAcceso, (codigoAcceso ?? '').trim());
  }

  /// URL base para las llamadas HTTP. Si el usuario ya configuró una en
  /// Ajustes, se usa esa (LAN o internet, según lo que haya escrito).
  /// Si no, cae a los valores típicos de desarrollo (emulador Android /
  /// localhost) para que la app siga siendo usable mientras se prueba
  /// en el emulador sin configurar nada todavía.
  Future<String> resolverBaseUrl() async {
    final url = await obtenerUrlBase();
    if (url != null) return url;

    if (kIsWeb) return 'http://127.0.0.1:$puertoPorDefecto';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:$puertoPorDefecto';
    } catch (_) {
      // Platform no disponible (p. ej. en algunos entornos de test).
    }
    return 'http://127.0.0.1:$puertoPorDefecto';
  }

  /// Header con el código de acceso (si hay uno configurado), listo
  /// para agregar a cualquier request de [ApiService].
  Future<Map<String, String>> headerCodigoAcceso() async {
    final codigo = await obtenerCodigoAcceso();
    return codigo == null ? {} : {'X-App-Key': codigo};
  }

  /// Prueba de conexión contra un endpoint protegido del backend, así
  /// valida en un solo paso que el servidor responde Y que el código de
  /// acceso (si el backend lo exige) es correcto. No lanza excepciones:
  /// siempre devuelve un resultado con `ok` y un mensaje listo para
  /// mostrar en la UI de Ajustes.
  Future<PruebaConexion> probarConexion({required String url, String? codigoAcceso}) async {
    final urlLimpia = url.trim();
    if (urlLimpia.isEmpty) {
      return const PruebaConexion(ok: false, mensaje: 'Escribe la dirección del servidor primero.');
    }

    final uri = Uri.parse('${_normalizarUrl(urlLimpia)}/cache/estadisticas');
    final headers = <String, String>{
      if (codigoAcceso != null && codigoAcceso.trim().isNotEmpty) 'X-App-Key': codigoAcceso.trim(),
    };

    try {
      final respuesta = await http.get(uri, headers: headers).timeout(const Duration(seconds: 45));
      if (respuesta.statusCode == 200) {
        return const PruebaConexion(ok: true, mensaje: 'Conexión exitosa con el servidor.');
      }
      if (respuesta.statusCode == 401) {
        return const PruebaConexion(
          ok: false,
          mensaje: 'El servidor respondió, pero el código de acceso es incorrecto.',
        );
      }
      return PruebaConexion(
        ok: false,
        mensaje: 'El servidor respondió con un error (código ${respuesta.statusCode}).',
      );
    } on SocketException {
      return const PruebaConexion(
        ok: false,
        mensaje: 'No se pudo conectar. Si es un servidor local, verifica que el '
            'teléfono y la PC estén en la misma Wi-Fi y que el backend esté '
            'encendido. Si es un servidor en internet, revisa la dirección.',
      );
    } on TimeoutException {
      return const PruebaConexion(
        ok: false,
        mensaje: 'El servidor no respondió a tiempo. Si acaba de "despertar" '
            '(planes gratuitos suelen dormirse), intenta de nuevo en un momento.',
      );
    } catch (e) {
      return PruebaConexion(ok: false, mensaje: 'No se pudo conectar: $e');
    }
  }
}

class PruebaConexion {
  const PruebaConexion({required this.ok, required this.mensaje});

  final bool ok;
  final String mensaje;
}
