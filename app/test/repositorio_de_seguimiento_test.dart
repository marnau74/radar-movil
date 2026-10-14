import 'dart:async';

import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radar_movil/src/datos/base_de_datos.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/red/errores.dart';

import 'ayudas.dart';

class _ApiFalsa extends Mock implements ApiDeSeguimiento;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late BaseDeDatos base;
  late _ApiFalsa api;
  late RepositorioDeSeguimiento repositorio;
  var momento = DateTime.utc(2026, 10, 13, 10);

  setUpAll(() => registerFallbackValue(seguimiento(0)));

  setUp(() {
    base = BaseDeDatos(NativeDatabase.memory());
    api = _ApiFalsa();
    momento = DateTime.utc(2026, 10, 13, 10);
    // Cada escritura un milisegundo después: así se distingue un cambio hecho mientras se subía otro.
    repositorio = RepositorioDeSeguimiento(
      base,
      api,
      reloj: () => momento = momento.add(const Duration(milliseconds: 1)),
    );
  });

  tearDown(() => base.close());

  /// Lo que haría el servidor: guardar y subir la versión.
  void servidorAcepta() => when(() => api.guardar(any())).thenAnswer((i) async {
    final s = i.positionalArguments.first as Seguimiento;
    return s.copyWith(version: (s.version ?? 0) + 1);
  });

  test('guardar sin red lo deja pendiente y se ve en la lista', () async {
    when(() => api.guardar(any())).thenThrow(const SinConexion());
    await repositorio.guardar(seguimiento(1));
    final resultado = await repositorio.sincronizar();

    expect(resultado.error, isA<SinConexion>());
    final lista = await repositorio.todos();
    expect(lista.single.estado, EstadoLocal.pendiente);
  });

  test('al volver la red se sube y queda sincronizado con la versión del servidor', () async {
    servidorAcepta();
    await repositorio.guardar(seguimiento(1));
    final resultado = await repositorio.sincronizar();

    expect(resultado.subidos, 1);
    final local = (await repositorio.todos()).single;
    expect(local.estado, EstadoLocal.sincronizado);
    expect(local.seguimiento.version, 1);
  });

  test('tres cambios sin red se suben como uno (la fila guarda el último estado)', () async {
    servidorAcepta();
    await repositorio.guardar(seguimiento(1));
    await repositorio.guardar(seguimiento(1, etapa: Etapa.preparando));
    await repositorio.guardar(seguimiento(1, etapa: Etapa.presentada));
    await repositorio.sincronizar();

    final enviado = verify(() => api.guardar(captureAny())).captured.single as Seguimiento;
    expect(enviado.etapa, Etapa.presentada);
  });

  test('un 409 deja el seguimiento en conflicto con las dos versiones', () async {
    final delServidor = seguimiento(1, etapa: Etapa.descartada, version: 4);
    when(() => api.guardar(any())).thenThrow(ConflictoDeVersion('Cambiado', delServidor));
    await repositorio.guardar(seguimiento(1, etapa: Etapa.presentada, version: 3));
    final resultado = await repositorio.sincronizar();

    expect(resultado.conflictos, 1);
    final local = (await repositorio.todos()).single;
    expect(local.enConflicto, isTrue);
    expect(local.seguimiento.etapa, Etapa.presentada);
    expect(local.delServidor, delServidor);
    expect(() => repositorio.guardar(seguimiento(1)), throwsStateError, reason: 'primero hay que resolverlo');
  });

  test('quedarme con lo mío vuelve a subir lo local sobre la versión del servidor', () async {
    when(() => api.guardar(any())).thenThrow(ConflictoDeVersion('Cambiado', seguimiento(1, version: 4)));
    await repositorio.guardar(seguimiento(1, etapa: Etapa.presentada, version: 3));
    await repositorio.sincronizar();

    servidorAcepta();
    await repositorio.quedarmeConLoMio(1);
    await repositorio.sincronizar();

    final enviado = verify(() => api.guardar(captureAny())).captured.last as Seguimiento;
    expect(enviado.version, 4);
    expect(enviado.etapa, Etapa.presentada);
    expect((await repositorio.todos()).single.seguimiento.version, 5);
  });

  test('usar lo del servidor descarta lo local; si allí se borró, se deja de seguir', () async {
    // El 1 se ha cambiado en otro dispositivo; el 2 se ha dejado de seguir allí.
    when(() => api.guardar(any())).thenAnswer((i) async {
      final s = i.positionalArguments.first as Seguimiento;
      throw ConflictoDeVersion('Cambiado', s.licitacionId == 1 ? seguimiento(1, version: 4) : null);
    });
    await repositorio.guardar(seguimiento(1, etapa: Etapa.presentada, version: 3));
    await repositorio.guardar(seguimiento(2, version: 2));
    await repositorio.sincronizar();

    await repositorio.usarLoDelServidor(1);
    await repositorio.usarLoDelServidor(2);
    final lista = await repositorio.todos();
    expect(lista.single.licitacionId, 1);
    expect(lista.single.estado, EstadoLocal.sincronizado);
    expect(lista.single.seguimiento.etapa, Etapa.interesa);
  });

  test('un cambio hecho mientras se subía otro no se pierde y no choca consigo mismo', () async {
    final subida = Completer<Seguimiento>();
    when(() => api.guardar(any())).thenAnswer((_) => subida.future);
    await repositorio.guardar(seguimiento(1, version: 1));
    final sincronizacion = repositorio.sincronizar();
    await pumpEventQueue();

    await repositorio.guardar(seguimiento(1, etapa: Etapa.ganada, version: 1));
    subida.complete(seguimiento(1, version: 2));
    await sincronizacion;

    final local = (await repositorio.todos()).single;
    expect(local.estado, EstadoLocal.pendiente);
    expect(local.seguimiento.etapa, Etapa.ganada);
    expect(local.seguimiento.version, 2, reason: 'la próxima subida va sobre la versión recién guardada');
  });

  test('dejar de seguir algo que nunca se subió no llama al servidor', () async {
    when(() => api.guardar(any())).thenThrow(const SinConexion());
    await repositorio.guardar(seguimiento(1));
    await repositorio.dejarDeSeguir(1);
    await repositorio.sincronizar();

    expect(await repositorio.todos(), isEmpty);
    verifyNever(() => api.borrar(any()));
  });

  test('dejar de seguir algo ya subido lo oculta y lo borra al sincronizar', () async {
    when(() => api.borrar(any())).thenAnswer((_) async {});
    await base.into(base.seguimientosLocales).insert(_fila(seguimiento(1, version: 2), EstadoLocal.sincronizado));
    await repositorio.dejarDeSeguir(1);
    expect(await repositorio.todos(), isEmpty, reason: 'ya no se enseña aunque falte borrarlo');

    await repositorio.sincronizar();
    verify(() => api.borrar(1)).called(1);
    expect(await base.select(base.seguimientosLocales).get(), isEmpty);
  });

  test('volver a seguir algo que se dejó de seguir sin red lo sube sobre la versión del servidor', () async {
    servidorAcepta();
    await base.into(base.seguimientosLocales).insert(_fila(seguimiento(1, version: 2), EstadoLocal.sincronizado));
    await repositorio.dejarDeSeguir(1);
    await repositorio.guardar(seguimiento(1));
    await repositorio.sincronizar();

    verifyNever(() => api.borrar(any()));
    final subido = verify(() => api.guardar(captureAny())).captured.single as Seguimiento;
    expect(subido.version, 2);
    expect((await repositorio.todos()).single.estado, EstadoLocal.sincronizado);
  });

  test('dos sincronizaciones a la vez suben cada cambio una sola vez', () async {
    servidorAcepta();
    await repositorio.guardar(seguimiento(1));
    await Future.wait([repositorio.sincronizar(), repositorio.sincronizar()]);
    verify(() => api.guardar(any())).called(1);
  });

  test('refrescar trae lo de otros dispositivos y respeta lo pendiente', () async {
    when(() => api.guardar(any())).thenThrow(const SinConexion());
    await base.into(base.seguimientosLocales).insert(_fila(seguimiento(3, version: 1), EstadoLocal.sincronizado));
    await repositorio.guardar(seguimiento(1, etapa: Etapa.preparando, version: 1));
    when(() => api.todos()).thenAnswer((_) async => [seguimiento(1, version: 1), seguimiento(2, version: 1)]);

    await repositorio.refrescar();
    final lista = {for (final s in await repositorio.todos()) s.licitacionId: s};
    expect(lista.keys, unorderedEquals([1, 2]), reason: 'el 3 se ha dejado de seguir en otro dispositivo');
    expect(lista[1]!.seguimiento.etapa, Etapa.preparando, reason: 'el cambio pendiente no se pisa');
    expect(lista[2]!.estado, EstadoLocal.sincronizado);
  });

  test('la lista va por plazo y lo que no tiene plazo, al final', () async {
    when(() => api.guardar(any())).thenThrow(const SinConexion());
    await repositorio.guardar(seguimiento(1, plazo: DateTime.utc(2026, 12)));
    await repositorio.guardar(seguimiento(2).copyWith(resumen: seguimiento(2).resumen.copyWith(plazo: null)));
    await repositorio.guardar(seguimiento(3, plazo: DateTime.utc(2026, 11)));
    expect((await repositorio.todos()).map((s) => s.licitacionId), [3, 1, 2]);
  });
}

SeguimientosLocalesCompanion _fila(Seguimiento s, EstadoLocal estado) => SeguimientosLocalesCompanion.insert(
  licitacionId: Value(s.licitacionId),
  datos: jsonEncode(s.toJson()),
  estado: estado,
  cambiadoEn: DateTime.utc(2026),
);
