@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/tema.dart';

import '../ayudas.dart';

/// La tarjeta de una licitación en claro y en oscuro. Las imágenes de referencia se generan en Linux (como en la CI):
/// `flutter test --tags golden --update-goldens` dentro de la imagen de Docker de Flutter (ver el README).
void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  final licitaciones = PaginaDeLicitaciones.fromJson(datos('busqueda.json')).elementos;

  for (final (nombre, tema) in [('clara', temaClaro()), ('oscura', temaOscuro())]) {
    testWidgets('tarjeta $nombre', (tester) async {
      tester.view
        ..physicalSize = const Size(1080, 1500)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 10))],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tema,
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TarjetaDeLicitacion(licitacion: licitaciones[0], alTocar: () {}, etapa: Etapa.preparando),
                  const SizedBox(height: 10),
                  TarjetaDeLicitacion(licitacion: licitaciones[1], alTocar: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(find.byType(ListView), matchesGoldenFile('tarjeta_$nombre.png'));
    });
  }
}
