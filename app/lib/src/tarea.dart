import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radar_movil/src/configuracion.dart';
import 'package:radar_movil/src/servicios.dart';
import 'package:workmanager/workmanager.dart';

const _tareaPeriodica = 'radar_movil.ponerAlDia';

/// Registra la tarea periódica (cada 6 horas, solo con red). Si ya estaba registrada, se deja como está.
Future<void> registrarTareaPeriodica() async {
  await Workmanager().initialize(despachadorDeTareas);
  await Workmanager().registerPeriodicTask(
    _tareaPeriodica,
    _tareaPeriodica,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Lo que ejecuta Android en segundo plano, en un isolate sin interfaz: monta los servicios a mano (sin Riverpod),
/// sincroniza, reprograma los avisos de plazo y avisa de lo nuevo de las alertas del radar.
@pragma('vm:entry-point')
void despachadorDeTareas() {
  Workmanager().executeTask((tarea, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await initializeDateFormatting('es_ES');
    final servicios = Servicios.reales(Configuracion.desdeEntorno());
    try {
      await servicios.notificador.iniciar();
      await servicios.sesion.cargar();
      await servicios.ponerAlDia();
      return true;
    } on Object catch (error, pila) {
      debugPrint('La tarea $tarea ha fallado: $error\n$pila');
      return false;
    } finally {
      await servicios.cerrar();
    }
  });
}
