import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radar_movil/src/app.dart';
import 'package:radar_movil/src/configuracion.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/servicios.dart';
import 'package:radar_movil/src/tarea.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');

  final servicios = Servicios.reales(Configuracion.desdeEntorno());
  await servicios.sesion.cargar();

  // Si la app la abre un aviso, empieza en la ficha de la licitación; si ya estaba abierta, navega a ella.
  GoRouter? router;
  await servicios.notificador.iniciar(alTocar: (ruta) => router?.go(ruta));
  router = crearRouter(inicial: await servicios.notificador.rutaDeArranque());

  unawaited(registrarTareaPeriodica());
  if (servicios.sesion.usuario != null) unawaited(servicios.sincronizar());

  runApp(
    ProviderScope(
      overrides: [serviciosProvider.overrideWithValue(servicios)],
      child: AppRadar(router: router),
    ),
  );
}
