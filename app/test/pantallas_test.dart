import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radar_movil/src/avisos/avisos_de_plazo.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/red/errores.dart';

import 'ayudas.dart';
import 'entorno.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    registerFallbackValue(seguimiento(0));
    registerFallbackValue(<AvisoProgramado>[]);
    registerFallbackValue(Orden.relevancia);
  });

  testWidgets('la búsqueda enseña los resultados del radar y su total', (tester) async {
    final e = Entorno();
    await e.arrancar(tester);

    expect(find.text('4 licitaciones'), findsOneWidget);
    expect(find.text('Sin plazo publicado'), findsNWidgets(2));
    expect(find.textContaining('Instituto Social de la Marina'), findsWidgets);
    expect(find.text('47.775 €'), findsOneWidget);
    expect(find.text('Cierra el 19 oct 2026'), findsOneWidget);
  });

  testWidgets('escribir busca al dejar de teclear y el filtro de plazo va en la petición', (tester) async {
    final e = Entorno();
    await e.arrancar(tester);

    await tester.enterText(find.byType(SearchBar), 'limpieza');
    await tester.pump(const Duration(milliseconds: 100));
    verifyNever(() => e.radar.buscar(texto: 'limpieza'));
    await tester.pump(const Duration(milliseconds: 400));
    await asentar(tester);
    verify(() => e.radar.buscar(texto: 'limpieza')).called(1);

    await tester.tap(find.text('Solo con plazo abierto'));
    await asentar(tester);
    verify(() => e.radar.buscar(texto: 'limpieza', soloAbiertas: false)).called(1);
  });

  testWidgets('sin resultados y sin red', (tester) async {
    final e = Entorno();
    when(
      () => e.radar.buscar(
        texto: any(named: 'texto'),
        soloAbiertas: any(named: 'soloAbiertas'),
        orden: any(named: 'orden'),
        pagina: any(named: 'pagina'),
      ),
    ).thenThrow(const SinConexion());
    await e.arrancar(tester);
    expect(find.text('Sin conexión'), findsOneWidget);

    when(
      () => e.radar.buscar(
        texto: any(named: 'texto'),
        soloAbiertas: any(named: 'soloAbiertas'),
        orden: any(named: 'orden'),
        pagina: any(named: 'pagina'),
      ),
    ).thenAnswer((_) async => const PaginaDeLicitaciones(elementos: [], pagina: 1, tamano: 20, total: 0, paginas: 0));
    await tester.tap(find.text('Reintentar'));
    await asentar(tester);
    expect(find.text('Ninguna licitación encaja'), findsOneWidget);
  });

  testWidgets('la ficha sin sesión invita a entrar para seguir', (tester) async {
    final e = Entorno();
    await e.arrancar(tester, inicial: '/licitaciones/20622372');

    expect(find.textContaining('Contratar la prestación de servicios'), findsOneWidget);
    expect(find.textContaining('Inicia sesión para seguir'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pliego de cláusulas administrativas'), 300);
    expect(find.text('3 lotes'), findsOneWidget);
  });

  testWidgets('seguir, cambiar de etapa y verlo en el embudo', (tester) async {
    final e = Entorno();
    await e.sesion.iniciar();
    await e.arrancar(tester);
    await tester.tap(find.textContaining('Contratar la prestación de servicios'));
    await asentar(tester);

    await tester.tap(find.text('Seguir esta licitación'));
    await asentar(tester);
    expect(find.text('Tu seguimiento'), findsOneWidget);
    verify(e.notificador.pedirPermiso).called(1);
    final avisos = verify(() => e.notificador.reprogramar(captureAny())).captured.last as List<AvisoProgramado>;
    expect(avisos.map((a) => a.tipo), [TipoDeAviso.tresDias, TipoDeAviso.unDia]);

    await tester.tap(find.byType(DropdownMenu<Etapa>));
    await asentar(tester);
    await tester.tap(find.text('Preparando la oferta').last);
    await asentar(tester);
    final subido = verify(() => e.api.guardar(captureAny())).captured.last as Seguimiento;
    expect(subido.etapa, Etapa.preparando);
    expect(subido.version, 1, reason: 'el cambio va sobre la versión que devolvió el servidor al crearlo');

    await tester.tap(find.byTooltip('Atrás'));
    await asentar(tester);
    await tester.tap(find.text('Seguimiento'));
    await asentar(tester);
    expect(find.text('Preparando la oferta · 1'), findsOneWidget);
    expect(find.text('47.775 €'), findsWidgets);
  });

  testWidgets('sin red el cambio se queda en el móvil y se avisa de que falta subirlo', (tester) async {
    final e = Entorno();
    when(() => e.api.guardar(any())).thenThrow(const SinConexion());
    await e.sesion.iniciar();
    await e.arrancar(tester);
    await tester.tap(find.textContaining('Contratar la prestación de servicios'));
    await asentar(tester);

    await tester.tap(find.text('Seguir esta licitación'));
    await asentar(tester);
    expect(find.byTooltip('Guardado en el móvil, pendiente de subir'), findsOneWidget);

    await tester.tap(find.byTooltip('Atrás'));
    await asentar(tester);
    await tester.tap(find.text('Seguimiento'));
    await asentar(tester);
    expect(find.textContaining('Un cambio guardado en el móvil, pendiente de subir.'), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
  });

  testWidgets('un conflicto enseña las dos versiones y deja elegir', (tester) async {
    final e = Entorno();
    // La primera subida choca con lo que otro dispositivo guardó; después, el servidor acepta.
    final delOtro = seguimiento(20622372, etapa: Etapa.descartada, version: 2, notas: 'No nos encaja');
    var subidas = 0;
    when(() => e.api.guardar(any())).thenAnswer((i) async {
      if (subidas++ == 0) throw ConflictoDeVersion('Cambiado', delOtro);
      final s = i.positionalArguments.first as Seguimiento;
      return s.copyWith(version: (s.version ?? 0) + 1);
    });
    await e.sesion.iniciar();
    await e.arrancar(tester, inicial: '/licitaciones/20622372');

    await tester.tap(find.text('Seguir esta licitación'));
    await asentar(tester);
    expect(find.text('Cambiado en otro dispositivo'), findsOneWidget);
    expect(find.text('No nos encaja'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Usar lo guardado'), 200);
    // Un toque mientras la lista aún se desliza solo la frena: primero se deja quieta.
    await asentar(tester);
    await tester.tap(find.text('Usar lo guardado'));
    await asentar(tester);
    expect(find.text('Cambiado en otro dispositivo'), findsNothing);
    await tester.scrollUntilVisible(find.text('Tu seguimiento'), -200);
    expect(find.text('Tu seguimiento'), findsOneWidget);
  });

  testWidgets('el editor valida y guarda notas y responsable', (tester) async {
    final e = Entorno();
    await e.sesion.iniciar();
    await e.servicios.seguimiento.guardar(seguimiento(20622372, version: 1));
    await e.arrancar(tester, inicial: '/licitaciones/20622372/seguimiento');

    await tester.enterText(find.widgetWithText(TextFormField, 'Responsable'), '  Luis  ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Notas'), 'Pedir presupuesto');
    await tester.tap(find.text('Guardar'));
    await asentar(tester);

    final guardado = verify(() => e.api.guardar(captureAny())).captured.last as Seguimiento;
    expect(guardado.responsable, 'Luis');
    expect(guardado.notas, 'Pedir presupuesto');
  });

  testWidgets('seguimiento y avisos sin sesión piden entrar', (tester) async {
    final e = Entorno();
    await e.arrancar(tester, inicial: '/seguimiento');
    expect(find.text('Iniciar sesión con tu cuenta del radar'), findsOneWidget);

    await tester.tap(find.text('Iniciar sesión con tu cuenta del radar'));
    await asentar(tester);
    expect(find.text('Aún no sigues ninguna licitación'), findsOneWidget);
    unawaited(e.sesion.dispose());
  });
}
