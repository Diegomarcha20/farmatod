import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/producto.dart';
import 'server_config_service.dart';

/// Excepción con un mensaje ya listo para mostrarse al usuario en la UI
/// (en español, sin detalles técnicos), lanzada por [ApiService] ante
/// cualquier fallo de red, timeout o respuesta inesperada del backend.
class ApiException implements Exception {
  final String mensaje;

  /// true solo cuando el backend nunca llegó a responder (sin ruta a
  /// la red, timeout, servidor caído): son los casos en los que tiene
  /// sentido caer al caché local en SQLite. false cuando el servidor
  /// sí respondió pero con un error (4xx/5xx) o un cuerpo inválido,
  /// donde mostrar un dato local desactualizado no sería correcto.
  final bool esErrorConectividad;

  const ApiException(this.mensaje, {this.esErrorConectividad = false});

  @override
  String toString() => mensaje;
}

class ApiService {
  ApiService({ServerConfigService? config})
      : _config = config ?? ServerConfigService.instancia;

  final ServerConfigService _config;

  /// Consulta `/buscar?q=<consulta>` en el backend.
  ///
  /// La URL base se resuelve en cada llamada desde [ServerConfigService]
  /// (lo que el usuario configuró en Ajustes), así que un cambio de IP
  /// aplica de inmediato, sin reiniciar la app.
  ///
  /// Si el backend está en un plan gratuito en la nube y estaba
  /// "dormido", la primera petición puede tardar en despertarlo y
  /// agotar el primer intento; por eso se reintenta una vez más antes
  /// de darse por vencido, en vez de mostrarle al usuario un error por
  /// algo que se resuelve solo con un segundo intento.
  ///
  /// Lanza siempre una [ApiException] con un mensaje amigable ante
  /// cualquier problema (sin conexión, timeout, servidor caído,
  /// respuesta malformada), para que la UI solo tenga que mostrar
  /// `e.mensaje` sin necesidad de interpretar excepciones técnicas.
  Future<BuscarResponse> buscar(String consulta) async {
    final baseUrl = await _config.resolverBaseUrl();
    final headerAcceso = await _config.headerCodigoAcceso();
    final uri = Uri.parse('$baseUrl/buscar').replace(
      queryParameters: {'q': consulta},
    );

    final response = await _solicitarConReintento(uri, headerAcceso);

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return BuscarResponse.fromJson(data as Map<String, dynamic>);
      } on FormatException {
        throw const ApiException(
          'El servidor envió una respuesta inválida. Intenta más tarde.',
        );
      } catch (_) {
        throw const ApiException(
          'No se pudo interpretar la respuesta del servidor.',
        );
      }
    }

    if (response.statusCode == 401) {
      throw const ApiException(
        'El código de acceso configurado en Ajustes es incorrecto o falta. '
        'Verifícalo y vuelve a intentar.',
      );
    }

    if (response.statusCode >= 500) {
      throw const ApiException(
        'El servidor tuvo un problema al procesar tu búsqueda. '
        'Intenta nuevamente en unos segundos.',
      );
    }

    throw ApiException(
      'No se pudo completar la búsqueda (código ${response.statusCode}). '
      'Intenta nuevamente.',
    );
  }

  Future<http.Response> _solicitarConReintento(Uri uri, Map<String, String> headerAcceso) async {
    const intentos = 2;
    const timeoutPorIntento = Duration(seconds: 40);

    for (var intento = 1; intento <= intentos; intento++) {
      try {
        return await http
            .get(uri, headers: {'Accept': 'application/json', ...headerAcceso})
            .timeout(timeoutPorIntento);
      } on SocketException {
        // Sin ruta a la red en absoluto: no tiene sentido reintentar,
        // un segundo intento fallaría exactamente igual e igual de rápido.
        throw const ApiException(
          'No tienes conexión a internet en este momento (o el servidor '
          'configurado en Ajustes no es alcanzable). Verifica tu Wi-Fi o '
          'datos móviles e intenta de nuevo.',
          esErrorConectividad: true,
        );
      } on TimeoutException {
        if (intento < intentos) {
          // Probable "despertar" de un backend gratuito en la nube: la
          // primera petición ya lo puso a arrancar, así que un segundo
          // intento inmediato suele encontrarlo despierto.
          continue;
        }
        throw const ApiException(
          'El servidor no respondió a tiempo, incluso tras reintentar. Si '
          'es un servidor gratuito en la nube, puede seguir despertando — '
          'espera un momento y vuelve a intentar. Si es local, revisa que '
          'esté encendido y en la misma red.',
          esErrorConectividad: true,
        );
      } on HttpException {
        throw const ApiException(
          'Ocurrió un problema al comunicarse con el servidor.',
          esErrorConectividad: true,
        );
      } on http.ClientException {
        throw const ApiException(
          'Ocurrió un problema de red al contactar el servidor.',
          esErrorConectividad: true,
        );
      } on FormatException {
        throw const ApiException('La dirección del servidor configurada en Ajustes es inválida.');
      }
    }

    // Inalcanzable en la práctica: el bucle siempre retorna o lanza.
    throw const ApiException('No se pudo completar la búsqueda.', esErrorConectividad: true);
  }
}
