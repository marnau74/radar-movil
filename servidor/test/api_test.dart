// Las respuestas JSON se recorren como `dynamic` a propósito: es lo que haría un cliente cualquiera.
// ignore_for_file: avoid_dynamic_calls
@Tags(['mongo'])
library;

import 'dart:convert';

import 'package:jose/jose.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:servidor/servidor.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

/// La API entera contra un MongoDB de verdad (los índices únicos y las escrituras condicionadas son justo lo que un
/// doble no comprobaría).
void main() {
  late Db db;
  late Handler api;
  late JsonWebKey clave;
  final errores = <Object>[];

  setUpAll(() async {
    db = await baseDePruebas();
    clave = claveDePrueba('clave-1');
    final repositorio = RepositorioDeSeguimientos(db);
    await repositorio.prepararIndices();
    api = crearApi(
      repositorio: repositorio,
      verificador: VerificadorDeTokens(emisor: emisor, audiencia: audiencia, cargarClaves: () async => jwks([clave])),
      alFallar: (error, _) => errores.add(error),
    );
  });

  setUp(() async {
    await db.collection(RepositorioDeSeguimientos.coleccion).deleteMany(<String, dynamic>{});
    errores.clear();
  });

  tearDown(() => expect(errores, isEmpty, reason: 'ninguna petición debe acabar en un 500'));

  tearDownAll(() async {
    await db.drop();
    await db.close();
  });

  Future<(int, dynamic)> llamar(String metodo, String ruta, {Object? cuerpo, String usuario = 'usuario-ana'}) async {
    final respuesta = await api(
      Request(
        metodo,
        Uri.parse('http://localhost/$ruta'),
        headers: {
          'authorization': 'Bearer ${token(clave, sub: usuario)}',
          'content-type': 'application/json',
        },
        body: cuerpo == null ? null : jsonEncode(cuerpo),
      ),
    );
    final texto = await respuesta.readAsString();
    return (respuesta.statusCode, texto.isEmpty ? null : jsonDecode(texto));
  }

  Map<String, dynamic> seguimiento({String etapa = 'interesa', int? version, double importe = 50000}) => {
    'resumen': {
      'titulo': 'Suministro de material de oficina',
      'organo': 'Diputación de Ejemplo',
      'expediente': 'EXP-2026/101',
      'importe': importe,
      'plazo': '2026-11-02T13:00:00Z',
    },
    'etapa': etapa,
    'notas': 'Pedir presupuesto al proveedor',
    'version': ?version,
  };

  test('/salud responde sin token', () async {
    final respuesta = await api(Request('GET', Uri.parse('http://localhost/salud')));
    expect(respuesta.statusCode, 200);
  });

  test('sin token, 401 con WWW-Authenticate', () async {
    final respuesta = await api(Request('GET', Uri.parse('http://localhost/seguimientos')));
    expect(respuesta.statusCode, 401);
    expect(respuesta.headers['www-authenticate'], 'Bearer');
    expect(respuesta.headers['content-type'], startsWith('application/problem+json'));
  });

  test('crear, leer, cambiar de etapa y borrar', () async {
    final (creado, uno) = await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento());
    expect(creado, 201);
    expect(uno, containsPair('version', 1));
    expect(uno['historial'], hasLength(1));

    final (cambiado, dos) = await llamar(
      'PUT',
      'seguimientos/101',
      cuerpo: seguimiento(etapa: 'preparando', version: 1),
    );
    expect(cambiado, 200);
    expect(dos['version'], 2);
    expect((dos['historial'] as List).last, containsPair('de', 'interesa'));

    final (leido, tres) = await llamar('GET', 'seguimientos/101');
    expect(leido, 200);
    expect(tres['etapa'], 'preparando');

    expect((await llamar('DELETE', 'seguimientos/101')).$1, 204);
    expect((await llamar('GET', 'seguimientos/101')).$1, 404);
  });

  test('cambiar las notas sin cambiar de etapa no añade historial', () async {
    await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento());
    final (_, cuerpo) = await llamar('PUT', 'seguimientos/101', cuerpo: {...seguimiento(version: 1), 'notas': 'Otra'});
    expect(cuerpo['historial'], hasLength(1));
    expect(cuerpo['notas'], 'Otra');
  });

  test('un cambio sobre una versión vieja es un conflicto y devuelve lo guardado', () async {
    await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento());
    await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento(etapa: 'preparando', version: 1));

    final (estado, cuerpo) = await llamar(
      'PUT',
      'seguimientos/101',
      cuerpo: seguimiento(etapa: 'descartada', version: 1),
    );
    expect(estado, 409);
    expect(cuerpo['actual'], containsPair('etapa', 'preparando'));
    expect(cuerpo['actual'], containsPair('version', 2));
  });

  test('crear dos veces el mismo es un conflicto, no un duplicado', () async {
    await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento());
    final (estado, cuerpo) = await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento(etapa: 'ganada'));
    expect(estado, 409);
    expect(cuerpo['actual'], containsPair('etapa', 'interesa'));
    expect(await db.collection(RepositorioDeSeguimientos.coleccion).count(), 1);
  });

  test('cambiar uno que se ha borrado es un conflicto sin versión actual', () async {
    final (estado, cuerpo) = await llamar('PUT', 'seguimientos/7', cuerpo: seguimiento(version: 3));
    expect(estado, 409);
    expect(cuerpo['actual'], isNull);
  });

  test('cada usuario ve solo lo suyo', () async {
    await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento());
    expect((await llamar('GET', 'seguimientos/101', usuario: 'usuario-luis')).$1, 404);
    expect((await llamar('GET', 'seguimientos', usuario: 'usuario-luis')).$2, isEmpty);
    expect((await llamar('DELETE', 'seguimientos/101', usuario: 'usuario-luis')).$1, 404);
    // Y el otro usuario puede seguir la misma licitación por su cuenta.
    expect((await llamar('PUT', 'seguimientos/101', cuerpo: seguimiento(), usuario: 'usuario-luis')).$1, 201);
  });

  test('la lista se filtra por etapa y va por plazo', () async {
    await llamar('PUT', 'seguimientos/1', cuerpo: seguimiento());
    await llamar('PUT', 'seguimientos/2', cuerpo: seguimiento(etapa: 'presentada'));
    final (_, todas) = await llamar('GET', 'seguimientos');
    expect(todas, hasLength(2));
    final (_, presentadas) = await llamar('GET', 'seguimientos?etapa=presentada');
    expect((presentadas as List).single['licitacionId'], 2);
    expect((await llamar('GET', 'seguimientos?etapa=rara')).$1, 400);
  });

  test('el embudo suma por etapa y calcula la tasa de éxito', () async {
    await llamar('PUT', 'seguimientos/1', cuerpo: seguimiento(etapa: 'ganada', importe: 1000));
    await llamar('PUT', 'seguimientos/2', cuerpo: seguimiento(etapa: 'perdida', importe: 2000));
    await llamar('PUT', 'seguimientos/3', cuerpo: seguimiento(etapa: 'perdida', importe: 500));
    await llamar(
      'PUT',
      'seguimientos/4',
      cuerpo: {
        ...seguimiento(),
        'resumen': {'titulo': 'Sin importe', 'organo': 'Ayuntamiento'},
      },
    );
    final (estado, embudo) = await llamar('GET', 'embudo');
    expect(estado, 200);
    final etapas = {for (final e in embudo['etapas'] as List) e['etapa']: e};
    expect(etapas['perdida'], containsPair('cuantas', 2));
    expect(etapas['perdida'], containsPair('importe', 2500));
    expect(etapas['interesa'], containsPair('importe', 0));
    expect(embudo['tasaDeExito'], closeTo(1 / 3, 1e-9));
  });

  group('peticiones malas', () {
    test('datos no válidos: 400 con todos los campos', () async {
      final (estado, cuerpo) = await llamar('PUT', 'seguimientos/101', cuerpo: {'etapa': 'x'});
      expect(estado, 400);
      expect((cuerpo['errores'] as List).map((e) => e['campo']), containsAll(['resumen', 'etapa']));
    });

    test('número de licitación no válido', () async {
      expect((await llamar('GET', 'seguimientos/abc')).$1, 400);
      expect((await llamar('GET', 'seguimientos/-3')).$1, 400);
    });

    test('JSON roto', () async {
      final respuesta = await api(
        Request(
          'PUT',
          Uri.parse('http://localhost/seguimientos/1'),
          headers: {'authorization': 'Bearer ${token(clave)}'},
          body: '{"etapa": ',
        ),
      );
      expect(respuesta.statusCode, 400);
    });

    test('cuerpo demasiado grande', () async {
      final (estado, _) = await llamar('PUT', 'seguimientos/1', cuerpo: {...seguimiento(), 'notas': 'x' * 70000});
      expect(estado, 400);
    });
  });
}
