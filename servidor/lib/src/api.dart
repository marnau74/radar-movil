import 'dart:async';
import 'dart:convert';

import 'package:servidor/src/autenticacion.dart';
import 'package:servidor/src/dominio.dart';
import 'package:servidor/src/repositorio.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Tamaño máximo de un cuerpo: un seguimiento ocupa unos pocos KB.
const int tamanoMaximo = 64 * 1024;

/// La API: todo exige sesión salvo `/salud`. Los errores van en formato RFC 9457 (`application/problem+json`).
Handler crearApi({
  required RepositorioDeSeguimientos repositorio,
  required VerificadorDeTokens verificador,
  void Function(Object error, StackTrace pila)? alFallar,
}) {
  final router = Router()
    ..get('/salud', (Request _) => _json(200, {'estado': 'ok'}))
    ..get('/seguimientos', (Request peticion) async {
      final texto = peticion.url.queryParameters['etapa'];
      final etapa = Etapa.deTexto(texto);
      if (texto != null && etapa == null) {
        return _problema(400, 'Petición no válida', 'Etapa desconocida: $texto');
      }
      final lista = await repositorio.deUsuario(_usuario(peticion).id, etapa: etapa);
      return _json(200, lista.map((s) => s.aJson()).toList());
    })
    ..get('/seguimientos/<id>', (Request peticion, String id) async {
      final seguimiento = await repositorio.uno(_usuario(peticion).id, _id(id));
      return seguimiento == null ? _noEncontrado(id) : _json(200, seguimiento.aJson());
    })
    ..put('/seguimientos/<id>', (Request peticion, String id) async {
      final cambio = CambioDeSeguimiento.validar(await _leerJson(peticion));
      final creado = cambio.version == null;
      final guardado = await repositorio.guardar(_usuario(peticion).id, _id(id), cambio);
      return _json(creado ? 201 : 200, guardado.aJson());
    })
    ..delete('/seguimientos/<id>', (Request peticion, String id) async {
      final borrado = await repositorio.borrar(_usuario(peticion).id, _id(id));
      return borrado ? Response(204) : _noEncontrado(id);
    })
    ..get('/embudo', (Request peticion) async {
      return _json(200, (await repositorio.embudo(_usuario(peticion).id)).aJson());
    });

  return const Pipeline()
      .addMiddleware(_errores(alFallar))
      .addMiddleware(_autenticacion(verificador))
      .addHandler(router.call);
}

const _claveUsuario = 'radar.usuario';

Usuario _usuario(Request peticion) => peticion.context[_claveUsuario]! as Usuario;

Middleware _autenticacion(VerificadorDeTokens verificador) =>
    (siguiente) => (peticion) async {
      if (peticion.url.path == 'salud') return await siguiente(peticion);
      final usuario = await verificador.verificar(peticion.headers['authorization']);
      return await siguiente(peticion.change(context: {_claveUsuario: usuario}));
    };

/// Traduce las excepciones a respuestas. Un error inesperado se registra y responde un 500 sin detalles.
Middleware _errores(void Function(Object, StackTrace)? alFallar) =>
    (siguiente) => (peticion) async {
      try {
        return await siguiente(peticion);
      } on TokenNoValido catch (e) {
        return _problema(401, 'No autorizado', e.motivo, cabeceras: {'www-authenticate': 'Bearer'});
      } on DatoNoValido catch (e) {
        return _problema(
          400,
          'Petición no válida',
          'Hay campos con valores no válidos',
          extra: {
            'errores': [
              for (final e in e.errores.entries) {'campo': e.key, 'mensaje': e.value},
            ],
          },
        );
      } on Conflicto catch (e) {
        return _problema(409, 'Conflicto', e.mensaje, extra: {'actual': e.actual?.aJson()});
      } on _PeticionMala catch (e) {
        return _problema(400, 'Petición no válida', e.mensaje);
      } on Object catch (error, pila) {
        alFallar?.call(error, pila);
        return _problema(500, 'Error interno', 'Ha ocurrido un error inesperado');
      }
    };

class _PeticionMala implements Exception {
  _PeticionMala(this.mensaje);

  final String mensaje;
}

int _id(String texto) {
  final id = int.tryParse(texto);
  if (id == null || id <= 0) throw _PeticionMala('El número de licitación no es válido: $texto');
  return id;
}

Future<Object?> _leerJson(Request peticion) async {
  final longitud = peticion.contentLength;
  if (longitud != null && longitud > tamanoMaximo) throw _PeticionMala('El cuerpo es demasiado grande');
  final bytes = <int>[];
  await for (final trozo in peticion.read()) {
    bytes.addAll(trozo);
    if (bytes.length > tamanoMaximo) throw _PeticionMala('El cuerpo es demasiado grande');
  }
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw _PeticionMala('El cuerpo no es JSON válido');
  }
}

Response _noEncontrado(String id) => _problema(404, 'No encontrado', 'No sigues la licitación $id');

Response _json(int estado, Object? cuerpo) =>
    Response(estado, body: jsonEncode(cuerpo), headers: {'content-type': 'application/json; charset=utf-8'});

Response _problema(
  int estado,
  String titulo,
  String detalle, {
  Map<String, Object?> extra = const {},
  Map<String, String> cabeceras = const {},
}) => Response(
  estado,
  body: jsonEncode({'type': 'about:blank', 'title': titulo, 'status': estado, 'detail': detalle, ...extra}),
  headers: {'content-type': 'application/problem+json; charset=utf-8', ...cabeceras},
);
