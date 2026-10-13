import 'package:dio/dio.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

/// Un dio con tiempos de espera razonables para el móvil y el token de la sesión en las peticiones que lo necesitan.
Dio crearDio(Uri base, Sesion sesion, {required bool Function(RequestOptions) necesitaSesion}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: base.toString(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'accept': 'application/json, application/problem+json'},
    ),
  );
  dio.interceptors.add(InterceptorDeSesion(sesion, dio, necesitaSesion: necesitaSesion));
  return dio;
}

/// Pone `Authorization: Bearer` y, si la API responde 401 (token revocado o reloj del móvil desfasado), refresca el
/// token y repite la petición una sola vez.
class InterceptorDeSesion extends QueuedInterceptor {
  InterceptorDeSesion(this._sesion, this._dio, {required this._necesitaSesion});

  static const _repetida = 'radar.repetida';

  final Sesion _sesion;
  final Dio _dio;
  final bool Function(RequestOptions) _necesitaSesion;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_necesitaSesion(options)) return handler.next(options);
    try {
      final token = await _sesion.token();
      if (token == null) {
        return handler.reject(DioException(requestOptions: options, error: const SesionCaducada()));
      }
      options.headers['authorization'] = 'Bearer $token';
      handler.next(options);
    } on Object catch (error) {
      // Sin red no se puede refrescar: se trata como cualquier otro fallo de conexión.
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError, error: error));
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opciones = err.requestOptions;
    if (err.response?.statusCode != 401 || !_necesitaSesion(opciones) || opciones.extra[_repetida] == true) {
      return handler.next(err);
    }
    try {
      final token = await _sesion.token(forzar: true);
      if (token == null) return handler.next(err);
      opciones
        ..headers['authorization'] = 'Bearer $token'
        ..extra[_repetida] = true;
      handler.resolve(await _dio.fetch<dynamic>(opciones));
    } on DioException catch (e) {
      handler.next(e);
    } on Object {
      handler.next(err);
    }
  }
}

/// El orden de los resultados de la búsqueda.
enum Orden {
  relevancia('Relevancia'),
  plazo('Cierre más próximo'),
  publicacion('Más recientes'),
  importe('Mayor importe');

  Orden(this.nombre);

  final String nombre;
}

/// La API pública del radar (búsqueda y ficha) y los avisos de sus alertas, que sí exigen sesión.
class ApiDelRadar {
  ApiDelRadar(this._dio);

  final Dio _dio;

  static bool necesitaSesion(RequestOptions o) => o.path.startsWith('/api/v1/avisos');

  Future<PaginaDeLicitaciones> buscar({
    String texto = '',
    bool soloAbiertas = true,
    Orden orden = Orden.relevancia,
    int pagina = 1,
    int tamano = 20,
  }) => conErrores(() async {
    final respuesta = await _dio.get<Map<String, dynamic>>(
      '/api/v1/licitaciones',
      queryParameters: {
        if (texto.trim().isNotEmpty) 'q': texto.trim(),
        if (soloAbiertas) 'abiertas': true,
        'orden': orden.name,
        'pagina': pagina,
        'tamano': tamano,
      },
    );
    return PaginaDeLicitaciones.fromJson(respuesta.data!);
  });

  Future<FichaDeLicitacion> ficha(int id) => conErrores(() async {
    final respuesta = await _dio.get<Map<String, dynamic>>('/api/v1/licitaciones/$id');
    return FichaDeLicitacion.fromJson(respuesta.data!);
  });

  Future<PaginaDeAvisos> avisos({int pagina = 1, bool soloNoLeidos = false}) => conErrores(() async {
    final respuesta = await _dio.get<Map<String, dynamic>>(
      '/api/v1/avisos',
      queryParameters: {'pagina': pagina, 'tamano': 20, 'soloNoLeidos': soloNoLeidos},
    );
    return PaginaDeAvisos.fromJson(respuesta.data!);
  });

  Future<int> avisosSinLeer() => conErrores(() async {
    final respuesta = await _dio.get<Map<String, dynamic>>('/api/v1/avisos/no-leidos');
    return (respuesta.data!['total'] as num).toInt();
  });

  Future<void> marcarAvisosLeidos() => conErrores(() => _dio.post<void>('/api/v1/avisos/leidos'));
}

/// El servidor del seguimiento (`servidor/`). Todo exige sesión.
class ApiDeSeguimiento {
  ApiDeSeguimiento(this._dio);

  final Dio _dio;

  static bool necesitaSesion(RequestOptions o) => o.path != '/salud';

  Future<List<Seguimiento>> todos() => conErrores(() async {
    final respuesta = await _dio.get<List<dynamic>>('/seguimientos');
    return [for (final s in respuesta.data!) Seguimiento.fromJson(s as Map<String, dynamic>)];
  });

  /// Crea (sin versión) o modifica (con la versión que se editó). Un 409 llega como [ConflictoDeVersion].
  Future<Seguimiento> guardar(Seguimiento seguimiento) => conErrores(() async {
    final respuesta = await _dio.put<Map<String, dynamic>>(
      '/seguimientos/${seguimiento.licitacionId}',
      data: seguimiento.cuerpoDelCambio(),
    );
    return Seguimiento.fromJson(respuesta.data!);
  });

  /// Deja de seguir. Si ya no existía (borrado desde otro dispositivo) no es un error.
  Future<void> borrar(int licitacionId) => conErrores(() async {
    try {
      await _dio.delete<void>('/seguimientos/$licitacionId');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
  });
}
