import 'package:flutter/foundation.dart';
import 'package:radar_movil/src/avisos/avisos_de_plazo.dart';
import 'package:radar_movil/src/avisos/notificador.dart';
import 'package:radar_movil/src/configuracion.dart';
import 'package:radar_movil/src/datos/base_de_datos.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/sesion/keycloak.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

/// Los servicios de la app, montados a mano. Los usan igual la interfaz (a través de Riverpod) y la tarea en
/// segundo plano, que arranca en otro isolate sin interfaz.
class Servicios {
  Servicios({
    required this.sesion,
    required this.base,
    required this.radar,
    required this.seguimiento,
    required this.notificador,
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  /// Con las implementaciones de verdad.
  factory Servicios.reales(Configuracion configuracion) {
    final sesion = Sesion(KeycloakConAppAuth(configuracion), AlmacenSeguro());
    final base = BaseDeDatos();
    return Servicios(
      sesion: sesion,
      base: base,
      radar: ApiDelRadar(crearDio(configuracion.radar, sesion, necesitaSesion: ApiDelRadar.necesitaSesion)),
      seguimiento: RepositorioDeSeguimiento(
        base,
        ApiDeSeguimiento(crearDio(configuracion.servidor, sesion, necesitaSesion: ApiDeSeguimiento.necesitaSesion)),
      ),
      notificador: Notificador(),
    );
  }

  static const _claveAlertas = 'avisos.alertasNotificadas';

  final Sesion sesion;
  final BaseDeDatos base;
  final ApiDelRadar radar;
  final RepositorioDeSeguimiento seguimiento;
  final Notificador notificador;
  final DateTime Function() _reloj;

  /// Deja programados los avisos de plazo de lo que se sigue ahora mismo.
  Future<void> reprogramarAvisos() async {
    try {
      await notificador.reprogramar(avisosDePlazo(await seguimiento.todos(), _reloj()));
    } on Object catch (error) {
      // Sin permiso de notificaciones o en un dispositivo sin alarmas: la app sigue funcionando sin avisos.
      debugPrint('No se han podido programar los avisos: $error');
    }
  }

  /// Sube lo pendiente, trae lo cambiado en otros dispositivos y reprograma los avisos. Si no hay red, se queda como
  /// está y se intentará más tarde.
  Future<ResultadoDeSincronizacion> sincronizar() async {
    final resultado = await seguimiento.sincronizar();
    if (resultado.error == null) {
      try {
        await seguimiento.refrescar();
      } on ErrorDeApi catch (e) {
        await reprogramarAvisos();
        return (subidos: resultado.subidos, conflictos: resultado.conflictos, error: e);
      }
    }
    await reprogramarAvisos();
    return resultado;
  }

  /// Lo que hace la tarea periódica: sincronizar y avisar si las alertas del radar han encontrado algo nuevo desde
  /// el último aviso.
  Future<void> ponerAlDia() async {
    if (sesion.usuario == null) return;
    await sincronizar();
    try {
      final sinLeer = await radar.avisosSinLeer();
      final avisadas = int.tryParse(await base.ajuste(_claveAlertas) ?? '') ?? 0;
      if (sinLeer > avisadas) await notificador.avisarDeAlertas(sinLeer);
      await base.fijarAjuste(_claveAlertas, '$sinLeer');
    } on ErrorDeApi catch (e) {
      debugPrint('No se han podido consultar los avisos del radar: $e');
    }
  }

  /// Al cerrar sesión no se queda nada de la cuenta en el móvil.
  Future<void> cerrarSesion() async {
    await sesion.cerrar();
    await seguimiento.borrarTodo();
    await base.fijarAjuste(_claveAlertas, '0');
    try {
      await notificador.cancelarTodo();
    } on Object catch (error) {
      debugPrint('No se han podido cancelar los avisos: $error');
    }
  }

  Future<void> cerrar() async {
    await sesion.dispose();
    await base.close();
  }
}
