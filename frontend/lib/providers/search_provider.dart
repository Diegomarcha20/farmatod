import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/producto.dart';
import '../services/api_service.dart';
import '../services/local_cache_service.dart';

enum SearchStatus { idle, loading, success, error, offline }

/// Estado de la búsqueda, compartido entre [HomeScreen] y [ResultScreen]
/// vía `provider`. Centraliza la llamada al backend y expone un estado
/// simple que la UI puede pintar directamente.
///
/// Resiliencia offline: si el Wi-Fi de la tienda falla, en vez de
/// mostrar solo un error se intenta resolver la búsqueda contra el
/// caché local en SQLite ([LocalCacheService]), que guarda el SKU y la
/// ubicación en el planograma de cada producto consultado con éxito.
/// La ficha de IA/scraping no se puede reconstruir sin conexión, así
/// que en ese caso se expone [SearchStatus.offline] para que la UI
/// muestre un aviso claro en lugar de datos de disponibilidad
/// potencialmente desactualizados.
class SearchProvider extends ChangeNotifier {
  SearchProvider(this._apiService, {LocalCacheService? cacheLocal})
      : _cacheLocal = cacheLocal ?? LocalCacheService.instancia;

  final ApiService _apiService;
  final LocalCacheService _cacheLocal;

  SearchStatus status = SearchStatus.idle;
  String? errorMessage;
  BuscarResponse? resultado;
  ProductoCacheado? productoOffline;
  String consultaActual = '';

  Future<void> buscar(String consulta) async {
    consultaActual = consulta.trim();
    if (consultaActual.isEmpty) return;

    status = SearchStatus.loading;
    errorMessage = null;
    productoOffline = null;
    notifyListeners();

    // Chequeo rápido de conectividad: si el dispositivo ya sabe que no
    // tiene red, no tiene sentido esperar los ~12s de timeout del
    // backend antes de caer al caché local.
    final tieneRed = await _hayConexionDeRed();
    if (!tieneRed) {
      await _resolverSinConexion(
        'No tienes conexión a internet en este momento (ni Wi-Fi ni datos móviles).',
      );
      return;
    }

    try {
      final respuesta = await _apiService.buscar(consultaActual);
      resultado = respuesta;
      status = SearchStatus.success;
      await _guardarEnCacheLocal(respuesta);
    } on ApiException catch (e) {
      if (e.esErrorConectividad) {
        await _resolverSinConexion(e.mensaje);
        return;
      }
      errorMessage = e.mensaje;
      status = SearchStatus.error;
    } catch (_) {
      errorMessage = 'Ocurrió un error inesperado. Intenta nuevamente.';
      status = SearchStatus.error;
    }

    notifyListeners();
  }

  Future<bool> _hayConexionDeRed() async {
    try {
      final resultados = await Connectivity().checkConnectivity();
      return resultados.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // Si el plugin de conectividad falla, no bloqueamos la búsqueda
      // por eso: se deja que el propio intento de red decida.
      return true;
    }
  }

  Future<void> _resolverSinConexion(String motivoRed) async {
    final cacheado = await _cacheLocal.buscar(consultaActual);
    if (cacheado != null) {
      productoOffline = cacheado;
      status = SearchStatus.offline;
    } else {
      errorMessage =
          '$motivoRed Tampoco hay un resultado guardado localmente para '
          '"$consultaActual".';
      status = SearchStatus.error;
    }
    notifyListeners();
  }

  Future<void> _guardarEnCacheLocal(BuscarResponse respuesta) async {
    if (!respuesta.encontrado || respuesta.producto == null) return;
    try {
      await _cacheLocal.guardar(respuesta.producto!);
      await _cacheLocal.guardarVarios(respuesta.alternativas);
    } catch (e) {
      debugPrint('No se pudo guardar en el caché local: $e');
    }
  }

  void reintentar() {
    if (consultaActual.isNotEmpty) {
      buscar(consultaActual);
    }
  }
}
