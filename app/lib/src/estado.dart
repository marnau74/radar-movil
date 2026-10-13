import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/modelos/embudo.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/servicios.dart';
import 'package:radar_movil/src/sesion/sesion.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'estado.g.dart';

/// Los servicios se crean en `main` (o en cada prueba) y se inyectan sobrescribiendo este provider.
@Riverpod(keepAlive: true)
Servicios servicios(Ref ref) => throw UnimplementedError('Se sobrescribe al arrancar la app');

@Riverpod(keepAlive: true)
DateTime Function() reloj(Ref ref) => DateTime.now;

/// Quién ha iniciado sesión (nulo si nadie). Cambia al entrar, al salir y cuando Keycloak deja de aceptar la sesión.
@Riverpod(keepAlive: true)
Stream<Usuario?> usuario(Ref ref) async* {
  final sesion = ref.watch(serviciosProvider).sesion;
  yield sesion.usuario;
  yield* sesion.cambios;
}

// ---------------------------------------------------------------------------------------------------------------
// Búsqueda

@immutable
class Criterios {
  const Criterios({this.texto = '', this.soloAbiertas = true, this.orden = Orden.relevancia});

  final String texto;
  final bool soloAbiertas;
  final Orden orden;

  Criterios copiar({String? texto, bool? soloAbiertas, Orden? orden}) => Criterios(
    texto: texto ?? this.texto,
    soloAbiertas: soloAbiertas ?? this.soloAbiertas,
    orden: orden ?? this.orden,
  );

  @override
  bool operator ==(Object other) =>
      other is Criterios && other.texto == texto && other.soloAbiertas == soloAbiertas && other.orden == orden;

  @override
  int get hashCode => Object.hash(texto, soloAbiertas, orden);
}

@riverpod
class CriteriosDeBusqueda extends _$CriteriosDeBusqueda {
  @override
  Criterios build() => const Criterios();

  // Un método y no un setter: es una acción sobre el estado, como las del resto de notifiers.
  // ignore: use_setters_to_change_properties
  void cambiar(Criterios criterios) => state = criterios;
}

/// Los resultados acumulados de las páginas cargadas.
@immutable
class Resultados {
  const Resultados(this.licitaciones, {required this.total, required this.pagina, required this.hayMas});

  final List<LicitacionResumen> licitaciones;
  final int total;
  final int pagina;
  final bool hayMas;
}

@riverpod
class Busqueda extends _$Busqueda {
  bool _cargandoMas = false;

  @override
  Future<Resultados> build() async {
    final criterios = ref.watch(criteriosDeBusquedaProvider);
    final pagina = await _pagina(criterios, 1);
    return Resultados(pagina.elementos, total: pagina.total, pagina: 1, hayMas: pagina.hayMas);
  }

  /// La página siguiente, al llegar al final de la lista. Si falla, se deja lo que había (se reintenta al volver a
  /// bajar).
  Future<void> cargarMas() async {
    final actuales = state.value;
    if (actuales == null || !actuales.hayMas || _cargandoMas) return;
    _cargandoMas = true;
    try {
      final siguiente = await _pagina(ref.read(criteriosDeBusquedaProvider), actuales.pagina + 1);
      if (!ref.mounted) return;
      state = AsyncData(
        Resultados(
          [...actuales.licitaciones, ...siguiente.elementos],
          total: siguiente.total,
          pagina: actuales.pagina + 1,
          hayMas: siguiente.hayMas,
        ),
      );
    } on ErrorDeApi catch (e) {
      debugPrint('No se ha podido cargar la página siguiente: $e');
    } finally {
      _cargandoMas = false;
    }
  }

  Future<PaginaDeLicitaciones> _pagina(Criterios c, int pagina) => ref
      .read(serviciosProvider)
      .radar
      .buscar(texto: c.texto, soloAbiertas: c.soloAbiertas, orden: c.orden, pagina: pagina);
}

@riverpod
Future<FichaDeLicitacion> ficha(Ref ref, int id) => ref.watch(serviciosProvider).radar.ficha(id);

// ---------------------------------------------------------------------------------------------------------------
// Seguimiento

/// Los seguimientos de la base local. Vacío sin sesión.
@riverpod
Stream<List<SeguimientoLocal>> seguimientos(Ref ref) {
  final usuario = ref.watch(usuarioProvider).value;
  if (usuario == null) return Stream.value(const []);
  return ref.watch(serviciosProvider).seguimiento.observar();
}

@riverpod
Stream<SeguimientoLocal?> seguimientoDe(Ref ref, int licitacionId) {
  final usuario = ref.watch(usuarioProvider).value;
  if (usuario == null) return Stream.value(null);
  return ref.watch(serviciosProvider).seguimiento.observarUno(licitacionId);
}

@riverpod
Embudo embudo(Ref ref) => Embudo.de(ref.watch(seguimientosProvider).value ?? const []);

/// Las acciones sobre el seguimiento. Cada cambio se guarda en local al momento (la pantalla responde aunque no haya
/// red) y después se intenta subir.
@Riverpod(keepAlive: true)
class Sincronizacion extends _$Sincronizacion {
  @override
  ResultadoDeSincronizacion? build() => null;

  Servicios get _s => ref.read(serviciosProvider);

  DateTime get _ahora => ref.read(relojProvider)();

  /// Empieza a seguir la licitación de la ficha. La primera vez pide permiso para los avisos de plazo.
  Future<void> seguir(FichaDeLicitacion ficha) async {
    final primera = (await _s.seguimiento.todos()).isEmpty;
    await _s.seguimiento.guardar(Seguimiento.nuevo(ficha.id, ResumenDeLicitacion.deLaFicha(ficha), _ahora));
    if (primera) unawaited(_s.notificador.pedirPermiso().catchError((Object _) => false));
    await sincronizar();
  }

  Future<void> guardar(Seguimiento seguimiento) async {
    await _s.seguimiento.guardar(seguimiento);
    await sincronizar();
  }

  /// Al abrir la ficha de algo que se sigue, se pone al día el resumen copiado (el plazo puede haber cambiado).
  Future<void> actualizarResumen(SeguimientoLocal local, FichaDeLicitacion ficha) async {
    final resumen = ResumenDeLicitacion.deLaFicha(ficha);
    if (local.enConflicto || local.seguimiento.resumen == resumen) return;
    await guardar(local.seguimiento.copyWith(resumen: resumen));
  }

  Future<void> dejarDeSeguir(int licitacionId) async {
    await _s.seguimiento.dejarDeSeguir(licitacionId);
    await sincronizar();
  }

  Future<void> quedarmeConLoMio(int licitacionId) async {
    await _s.seguimiento.quedarmeConLoMio(licitacionId);
    await sincronizar();
  }

  Future<void> usarLoDelServidor(int licitacionId) async {
    await _s.seguimiento.usarLoDelServidor(licitacionId);
    await _s.reprogramarAvisos();
  }

  Future<ResultadoDeSincronizacion> sincronizar() async {
    final resultado = await _s.sincronizar();
    if (ref.mounted) state = resultado;
    return resultado;
  }
}

/// Cuántos cambios faltan por subir y cuántos conflictos hay, para el aviso de la pantalla del seguimiento.
@riverpod
({int pendientes, int conflictos}) estadoLocal(Ref ref) {
  final lista = ref.watch(seguimientosProvider).value ?? const [];
  return (pendientes: lista.where((s) => s.pendiente).length, conflictos: lista.where((s) => s.enConflicto).length);
}

// ---------------------------------------------------------------------------------------------------------------
// Avisos del radar

@riverpod
Future<PaginaDeAvisos?> avisosDelRadar(Ref ref) {
  final usuario = ref.watch(usuarioProvider).value;
  if (usuario == null) return Future.value();
  return ref.watch(serviciosProvider).radar.avisos();
}
