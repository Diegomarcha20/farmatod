import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notificaciones locales de "producto próximo a vencer" -programadas
/// en el propio teléfono (no dependen del backend ni de conexión: una
/// vez programada, la notificación suena aunque la app esté cerrada o
/// no haya internet-.
///
/// Usa `AndroidScheduleMode.inexactAllowWhileIdle`: no llega al
/// segundo exacto (puede variar unos minutos), pero no exige el
/// permiso especial de "alarmas exactas" que Android restringe mucho
/// más -de sobra para avisar "ya se acerca la fecha", no hace falta
/// precisión de alarma-.
class NotificationService {
  NotificationService._interno();

  static final NotificationService instancia = NotificationService._interno();

  static const _canalId = 'vencimientos';
  static const _canalNombre = 'Productos próximos a vencer';
  static const _canalDescripcion = 'Avisos para retirar del anaquel productos que se acercan a su fecha de vencimiento.';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inicializado = false;

  /// Nunca lanza una excepción hacia quien la llama -ni la falta de
  /// registro de plugins nativos (ej. corriendo en `flutter_test`, que
  /// no tiene canales de plataforma reales) ni un permiso denegado
  /// deben tumbar el resto de la app-. Si falla, `_inicializado` queda
  /// en `false` y las llamadas siguientes simplemente no hacen nada.
  Future<void> inicializar() async {
    if (_inicializado) return;

    try {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('America/Caracas'));
      } catch (_) {
        // Si por algún motivo no está ese dato de zona horaria empaquetado,
        // se sigue con la zona por defecto del paquete en vez de fallar
        // toda la inicialización -las notificaciones seguirían funcionando,
        // solo con la hora del dispositivo tal cual-.
      }

      const configuracionAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const configuracion = InitializationSettings(android: configuracionAndroid);
      await _plugin.initialize(configuracion);

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _inicializado = true;
    } catch (_) {
      _inicializado = false;
    }
  }

  /// Programa el aviso para retirar un lote del anaquel. `id` debe ser
  /// único por lote (se usa el propio id del lote en la base de datos
  /// local). Si `fecha` ya pasó, la notificación se muestra casi de
  /// inmediato -Android no rechaza fechas pasadas, las dispara en la
  /// próxima oportunidad-, lo cual es el comportamiento correcto para
  /// un lote que se agrega ya vencido o a punto de vencer.
  ///
  /// Nunca lanza una excepción: si programar la notificación falla
  /// (ej. permiso denegado), el lote igual queda guardado en el
  /// inventario y visible en "Próximos a vencer", solo sin el aviso
  /// automático -mejor eso que perder el registro completo-.
  Future<void> programarAvisoVencimiento({
    required int id,
    required String nombreProducto,
    required DateTime fecha,
  }) async {
    await inicializar();
    if (!_inicializado) return;

    const detalles = NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNombre,
        channelDescription: _canalDescripcion,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id,
        'Producto próximo a vencer',
        '$nombreProducto: retíralo del anaquel.',
        tz.TZDateTime.from(fecha, tz.local),
        detalles,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Mejor esfuerzo: el lote ya está guardado de todas formas.
    }
  }

  Future<void> cancelarAviso(int id) async {
    if (!_inicializado) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {
      // No hay nada más que hacer si falla cancelar un aviso que quizás
      // ni siquiera llegó a programarse.
    }
  }
}
