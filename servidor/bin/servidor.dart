import 'dart:async';
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:servidor/servidor.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Arranca el servidor con la configuración de las variables de entorno (ver `.env.ejemplo` en la raíz).
///
/// Con el argumento `salud` solo comprueba que el servidor que ya está en marcha responde: es la comprobación de
/// salud de Docker, que no puede usar curl porque la imagen no lleva nada más que el ejecutable.
Future<void> main(List<String> argumentos) async {
  final entorno = Platform.environment;
  final puerto = int.parse(entorno['RADAR_MOVIL_PUERTO'] ?? '8090');
  if (argumentos.contains('salud')) exit(await _responde(puerto) ? 0 : 1);
  String obligatoria(String nombre) => entorno[nombre] ?? (throw StateError('Falta la variable de entorno $nombre'));

  final db = await Db.create(obligatoria('RADAR_MOVIL_MONGO_URL'));
  await db.open();
  final repositorio = RepositorioDeSeguimientos(db);
  await repositorio.prepararIndices();

  final verificador = VerificadorDeTokens.conJwks(
    emisor: obligatoria('RADAR_OIDC_EMISOR'),
    audiencia: entorno['RADAR_OIDC_AUDIENCIA'] ?? 'radar-api',
    jwks: Uri.parse(obligatoria('RADAR_OIDC_JWKS')),
  );

  final api = crearApi(
    repositorio: repositorio,
    verificador: verificador,
    alFallar: (error, pila) => stderr.writeln('Error no controlado: $error\n$pila'),
  );
  final servidor = await io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(api),
    InternetAddress.anyIPv4,
    puerto,
  );
  stdout.writeln('Radar móvil escuchando en el puerto ${servidor.port}');

  // Parada ordenada (Docker manda SIGTERM): se terminan las peticiones en curso y se cierra MongoDB.
  late final StreamSubscription<ProcessSignal> senal;
  senal = (Platform.isWindows ? ProcessSignal.sigint.watch() : ProcessSignal.sigterm.watch()).listen((_) async {
    await senal.cancel();
    await servidor.close();
    await db.close();
    exit(0);
  });
}

Future<bool> _responde(int puerto) async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final respuesta = await (await cliente.getUrl(Uri.parse('http://127.0.0.1:$puerto/salud'))).close();
    await respuesta.drain<void>();
    return respuesta.statusCode == 200;
  } on Object {
    return false;
  } finally {
    cliente.close(force: true);
  }
}
