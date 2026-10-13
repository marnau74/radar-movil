import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:radar_movil/src/avisos/avisos_de_plazo.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Los avisos en el móvil, sin Firebase ni servidor de notificaciones: los de plazo se programan en local con la
/// alarma del sistema y los de las alertas del radar los lanza la tarea periódica.
class Notificador {
  Notificador([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _canalPlazos = AndroidNotificationDetails(
    'plazos',
    'Plazos de tus seguimientos',
    channelDescription: 'Cuando está a punto de cerrar el plazo de una licitación que sigues',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_aviso',
  );

  static const _canalAlertas = AndroidNotificationDetails(
    'alertas',
    'Novedades de tus alertas',
    channelDescription: 'Licitaciones nuevas que encajan con las alertas que tienes en el radar',
    icon: 'ic_aviso',
  );

  final FlutterLocalNotificationsPlugin _plugin;

  /// Prepara el plugin y la zona horaria del móvil (los avisos de plazo se programan en hora local).
  Future<void> iniciar({void Function(String ruta)? alTocar}) async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } on Object catch (error) {
      debugPrint('Zona horaria desconocida, se usa Europe/Madrid: $error');
      tz.setLocalLocation(tz.getLocation('Europe/Madrid'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_aviso')),
      onDidReceiveNotificationResponse: (respuesta) {
        final ruta = respuesta.payload;
        if (ruta != null) alTocar?.call(ruta);
      },
    );
  }

  /// La ruta del aviso que ha abierto la app, si la ha abierto un aviso.
  Future<String?> rutaDeArranque() async {
    final detalles = await _plugin.getNotificationAppLaunchDetails();
    return detalles?.didNotificationLaunchApp ?? false ? detalles?.notificationResponse?.payload : null;
  }

  /// Pide permiso para avisar (Android 13 o posterior). Se pide al seguir la primera licitación, que es cuando se
  /// entiende para qué es.
  Future<bool> pedirPermiso() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission() ??
      true;

  /// Deja programados exactamente estos avisos de plazo: cancela los que sobran y programa (o reprograma, con el
  /// mismo identificador) el resto.
  Future<void> reprogramar(List<AvisoProgramado> avisos) async {
    final ids = avisos.map((a) => a.id).toSet();
    for (final pendiente in await _plugin.pendingNotificationRequests()) {
      if (pendiente.id != idDeAvisoDeAlertas && !ids.contains(pendiente.id)) await _plugin.cancel(id: pendiente.id);
    }
    for (final aviso in avisos) {
      await _plugin.zonedSchedule(
        id: aviso.id,
        scheduledDate: tz.TZDateTime.from(aviso.cuando, tz.local),
        notificationDetails: const NotificationDetails(android: _canalPlazos),
        // Inexacto: unos minutos de margen no importan para un plazo de días y no hace falta pedir alarmas exactas.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: aviso.titulo,
        body: aviso.texto,
        payload: aviso.ruta,
      );
    }
  }

  Future<void> avisarDeAlertas(int sinLeer) => _plugin.show(
    id: idDeAvisoDeAlertas,
    title: sinLeer == 1 ? 'Una licitación nueva en tus alertas' : '$sinLeer licitaciones nuevas en tus alertas',
    body: 'Toca para verlas',
    notificationDetails: const NotificationDetails(android: _canalAlertas),
    payload: '/avisos',
  );

  Future<void> cancelarTodo() => _plugin.cancelAll();
}
