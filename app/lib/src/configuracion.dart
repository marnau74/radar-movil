/// Las direcciones de los servicios. Se cambian al compilar con `--dart-define` (ver el README).
///
/// Los valores por defecto son los del entorno local: en el emulador, `localhost` es el propio emulador, así que hay
/// que redirigir los puertos con `adb reverse tcp:8088 tcp:8088` y `adb reverse tcp:8090 tcp:8090`. Se hace así, y no
/// con `10.0.2.2`, porque el emisor de los tokens tiene que ser exactamente el mismo que ve el servidor.
class Configuracion {
  const Configuracion({
    required this.radar,
    required this.servidor,
    required this.emisor,
    this.cliente = 'radar-movil',
    this.redireccion = 'es.radarlicitaciones.movil:/oauth2redirect',
  });

  factory Configuracion.desdeEntorno() => Configuracion(
    radar: Uri.parse(const String.fromEnvironment('RADAR_URL', defaultValue: 'http://localhost:8088')),
    servidor: Uri.parse(const String.fromEnvironment('RADAR_MOVIL_URL', defaultValue: 'http://localhost:8090')),
    emisor: const String.fromEnvironment('RADAR_OIDC_EMISOR', defaultValue: 'http://localhost:8088/auth/realms/radar'),
  );

  /// La web del radar (su API está en `/api/v1`).
  final Uri radar;

  /// El servidor del seguimiento.
  final Uri servidor;
  final String emisor;
  final String cliente;
  final String redireccion;
}
