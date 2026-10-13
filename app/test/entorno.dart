import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radar_movil/src/app.dart';
import 'package:radar_movil/src/avisos/notificador.dart';
import 'package:radar_movil/src/datos/base_de_datos.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/servicios.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

import 'ayudas.dart';

class RadarFalso extends Mock implements ApiDelRadar;

class ApiDeSeguimientoFalsa extends Mock implements ApiDeSeguimiento;

class NotificadorFalso extends Mock implements Notificador;

/// La app entera con dobles en los bordes (APIs, Keycloak, notificaciones) y la base de datos en memoria.
class Entorno {
  Entorno() {
    when(
      () => radar.buscar(
        texto: any(named: 'texto'),
        soloAbiertas: any(named: 'soloAbiertas'),
        orden: any(named: 'orden'),
        pagina: any(named: 'pagina'),
      ),
    ).thenAnswer((_) async => PaginaDeLicitaciones.fromJson(datos('busqueda.json')));
    when(() => radar.ficha(any())).thenAnswer((_) async => FichaDeLicitacion.fromJson(datos('ficha.json')));
    // El servidor de mentira guarda de verdad: al refrescar devuelve lo que se ha subido.
    when(() => api.guardar(any())).thenAnswer((i) async {
      final s = i.positionalArguments.first as Seguimiento;
      return enServidor[s.licitacionId] = s.copyWith(version: (s.version ?? 0) + 1);
    });
    when(api.todos).thenAnswer((_) async => enServidor.values.toList());
    when(() => notificador.reprogramar(any())).thenAnswer((_) async {});
    when(notificador.pedirPermiso).thenAnswer((_) async => true);
  }

  final ahora = DateTime(2026, 10, 13, 10);
  final enServidor = <int, Seguimiento>{};
  final radar = RadarFalso();
  final api = ApiDeSeguimientoFalsa();
  final notificador = NotificadorFalso();
  late final proveedor = ProveedorFalso(() => ahora);
  late final sesion = Sesion(proveedor, AlmacenEnMemoria(), reloj: () => ahora);
  // Los streams se cierran en el acto: si no, drift deja un temporizador vivo al terminar cada prueba.
  final base = BaseDeDatos(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));

  late final servicios = Servicios(
    sesion: sesion,
    base: base,
    radar: radar,
    seguimiento: RepositorioDeSeguimiento(base, api, reloj: () => ahora),
    notificador: notificador,
    reloj: () => ahora,
  );

  Future<void> arrancar(WidgetTester tester, {String inicial = '/'}) async {
    addTearDown(base.close);
    // Un móvil normal (360 × 800 dp), no la ventana de 800 × 600 que usa Flutter por defecto en las pruebas.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviciosProvider.overrideWithValue(servicios), relojProvider.overrideWithValue(() => ahora)],
        child: AppRadar(router: crearRouter(inicial: inicial)),
      ),
    );
    await asentar(tester);
  }
}

/// drift programa temporizadores y `pumpAndSettle` solo avanza el reloj simulado mientras hay fotogramas pendientes:
/// sin esto, una escritura en la base de datos se quedaría a medias. Se avanza el reloj y después se asienta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}
