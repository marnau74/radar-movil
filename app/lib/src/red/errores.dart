import 'package:dio/dio.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';

/// Los errores de las dos APIs, ya traducidos a lo que la app necesita distinguir. Las dos responden con el formato
/// RFC 9457 (`application/problem+json`), así que el detalle viene en `detail`.
sealed class ErrorDeApi implements Exception {
  const ErrorDeApi(this.mensaje);

  final String mensaje;

  @override
  String toString() => 'ErrorDeApi: $mensaje';
}

/// No hay red o el servidor no responde. Lo que se haya cambiado se queda pendiente de subir.
class SinConexion extends ErrorDeApi {
  const SinConexion() : super('Sin conexión. Lo verás actualizado cuando vuelva la red.');
}

/// No hay sesión o Keycloak ya no la acepta.
class SesionCaducada extends ErrorDeApi {
  const SesionCaducada() : super('Tu sesión ha caducado. Vuelve a iniciar sesión.');
}

class NoEncontrado extends ErrorDeApi {
  const NoEncontrado(super.mensaje);
}

class DatosNoValidos extends ErrorDeApi {
  const DatosNoValidos(super.mensaje, this.errores);

  /// Campo → mensaje.
  final Map<String, String> errores;
}

/// El seguimiento ha cambiado en otro dispositivo (o ya se seguía). [actual] es lo guardado, o nulo si se ha borrado.
class ConflictoDeVersion extends ErrorDeApi {
  const ConflictoDeVersion(super.mensaje, this.actual);

  final Seguimiento? actual;
}

class ErrorDelServidor extends ErrorDeApi {
  const ErrorDelServidor(super.mensaje, {this.estado});

  final int? estado;
}

/// Convierte un error de dio en uno de la app. Lo que no es un error HTTP conocido se deja pasar.
ErrorDeApi traducirError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return const SinConexion();
    case DioExceptionType.badResponse:
      break;
    case DioExceptionType.transformTimeout:
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return e.error is ErrorDeApi ? e.error! as ErrorDeApi : const SinConexion();
  }
  final respuesta = e.response!;
  final cuerpo = respuesta.data is Map<String, dynamic>
      ? respuesta.data as Map<String, dynamic>
      : const <String, dynamic>{};
  final detalle = cuerpo['detail'] as String? ?? 'Error ${respuesta.statusCode}';
  return switch (respuesta.statusCode) {
    401 => const SesionCaducada(),
    404 => NoEncontrado(detalle),
    400 => DatosNoValidos(detalle, {
      for (final error in (cuerpo['errores'] as List? ?? const []).cast<Map<String, dynamic>>())
        error['campo'] as String: error['mensaje'] as String,
    }),
    409 => ConflictoDeVersion(
      detalle,
      cuerpo['actual'] == null ? null : Seguimiento.fromJson(cuerpo['actual'] as Map<String, dynamic>),
    ),
    final estado => ErrorDelServidor(
      estado != null && estado >= 500 ? 'El servidor ha tenido un problema. Inténtalo más tarde.' : detalle,
      estado: estado,
    ),
  };
}

/// Ejecuta una petición y traduce sus errores.
Future<T> conErrores<T>(Future<T> Function() peticion) async {
  try {
    return await peticion();
  } on DioException catch (e) {
    throw traducirError(e);
  }
}
