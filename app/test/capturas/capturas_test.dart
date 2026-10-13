@Tags(['capturas'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radar_movil/src/avisos/avisos_de_plazo.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/ui/tema.dart';

import '../ayudas.dart';
import '../entorno.dart';

/// Las capturas del README, dibujadas con la fuente de la app (IBM Plex Sans) y los iconos de Material a partir de respuestas
/// reales del radar. No comprueban nada: se generan a mano, en Linux, con
/// `flutter test --run-skipped --tags capturas --update-goldens`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    registerFallbackValue(seguimiento(0));
    registerFallbackValue(<AvisoProgramado>[]);
    registerFallbackValue(Orden.relevancia);
    Future<void> cargar(String familia, List<String> archivos) async {
      final cargador = FontLoader(familia);
      for (final archivo in archivos) {
        cargador.addFont(Future.value(ByteData.sublistView(File(archivo).readAsBytesSync())));
      }
      await cargador.load();
    }

    await cargar(fuente, [
      for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fuentes/IBMPlexSans-$peso.ttf',
    ]);
    // Los iconos de Material vienen con Flutter.
    await cargar('MaterialIcons', [
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  /// Un embudo con varias licitaciones reales de la búsqueda, cada una en una etapa.
  Future<void> sembrar(Entorno e) async {
    final licitaciones = PaginaDeLicitaciones.fromJson(datos('busqueda.json')).elementos;
    final ficha = FichaDeLicitacion.fromJson(datos('ficha.json'));
    final etapas = [Etapa.preparando, Etapa.interesa, Etapa.presentada];
    for (final (i, l) in licitaciones.indexed) {
      await e.servicios.seguimiento.guardar(
        Seguimiento(
          licitacionId: l.id,
          resumen: ResumenDeLicitacion(
            titulo: l.titulo,
            organo: l.organo,
            importe: l.importeSinIva,
            plazo: l.plazoPresentacion,
          ),
          etapa: etapas[i % etapas.length],
          responsable: l.id == ficha.id ? 'Laura' : null,
          notas: l.id == ficha.id ? 'Pedir presupuesto del lote 2 antes del viernes.' : '',
        ),
      );
    }
    await e.servicios.sincronizar();
  }

  Future<void> capturar(WidgetTester tester, String nombre) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('../../../docs/capturas/$nombre.png'));

  testWidgets('búsqueda', (tester) async {
    final e = Entorno();
    await e.sesion.iniciar();
    await e.arrancar(tester);
    await sembrar(e);
    await asentar(tester);
    await capturar(tester, 'busqueda');
  });

  testWidgets('ficha con seguimiento', (tester) async {
    final e = Entorno();
    await e.sesion.iniciar();
    await e.arrancar(tester);
    await sembrar(e);
    await tester.tap(find.textContaining('Contratar la prestación de servicios'));
    await asentar(tester);
    await capturar(tester, 'ficha');
  });

  testWidgets('embudo', (tester) async {
    final e = Entorno();
    await e.sesion.iniciar();
    await e.arrancar(tester, inicial: '/seguimiento');
    await sembrar(e);
    await asentar(tester);
    await capturar(tester, 'seguimiento');
  });

  testWidgets('embudo en oscuro', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final e = Entorno();
    await e.sesion.iniciar();
    await e.arrancar(tester, inicial: '/seguimiento');
    await sembrar(e);
    await asentar(tester);
    await capturar(tester, 'seguimiento-oscuro');
  });
}
