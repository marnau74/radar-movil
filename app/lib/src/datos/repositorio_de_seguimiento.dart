import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:radar_movil/src/datos/base_de_datos.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/red/errores.dart';

/// Un seguimiento tal como está en el móvil.
@immutable
class SeguimientoLocal {
  const SeguimientoLocal(this.seguimiento, this.estado, {this.delServidor});

  final Seguimiento seguimiento;
  final EstadoLocal estado;

  /// En un conflicto, lo que tiene el servidor (nulo si allí se ha borrado).
  final Seguimiento? delServidor;

  int get licitacionId => seguimiento.licitacionId;

  bool get pendiente => estado == EstadoLocal.pendiente || estado == EstadoLocal.borrando;

  bool get enConflicto => estado == EstadoLocal.conflicto;

  @override
  bool operator ==(Object other) =>
      other is SeguimientoLocal &&
      other.seguimiento == seguimiento &&
      other.estado == estado &&
      other.delServidor == delServidor;

  @override
  int get hashCode => Object.hash(seguimiento, estado, delServidor);
}

/// Cómo ha ido una sincronización.
typedef ResultadoDeSincronizacion = ({int subidos, int conflictos, ErrorDeApi? error});

/// El seguimiento sin conexión: la app lee y escribe siempre en la base local y los cambios se suben cuando hay red.
///
/// Si al subir un cambio el servidor tiene otra versión (se ha cambiado en otro dispositivo), no se pisa: el
/// seguimiento queda en conflicto con las dos versiones hasta que el usuario elige.
class RepositorioDeSeguimiento {
  RepositorioDeSeguimiento(this._db, this._api, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final BaseDeDatos _db;
  final ApiDeSeguimiento _api;
  final DateTime Function() _reloj;

  Future<ResultadoDeSincronizacion>? _sincronizando;

  $SeguimientosLocalesTable get _tabla => _db.seguimientosLocales;

  /// Los que se siguen (no los que se están dejando de seguir), por plazo: lo que antes cierra, primero.
  Stream<List<SeguimientoLocal>> observar() => (_db.select(
    _tabla,
  )..where((t) => t.estado.equalsValue(EstadoLocal.borrando).not())).watch().map((filas) => _ordenar(filas.map(_leer)));

  Stream<SeguimientoLocal?> observarUno(int licitacionId) =>
      (_db.select(_tabla)
            ..where((t) => t.licitacionId.equals(licitacionId) & t.estado.equalsValue(EstadoLocal.borrando).not()))
          .watchSingleOrNull()
          .map((fila) => fila == null ? null : _leer(fila));

  Future<List<SeguimientoLocal>> todos() async => _ordenar(
    (await (_db.select(_tabla)..where((t) => t.estado.equalsValue(EstadoLocal.borrando).not())).get()).map(_leer),
  );

  /// Guarda en local y lo deja pendiente de subir. No espera a la red: quien llama sincroniza después.
  Future<void> guardar(Seguimiento seguimiento) async {
    final actual = await _fila(seguimiento.licitacionId);
    if (actual?.estado == EstadoLocal.conflicto) {
      throw StateError('Hay que resolver el conflicto antes de volver a cambiarlo');
    }
    // Se ha vuelto a seguir algo que se había dejado de seguir sin red: en el servidor sigue existiendo, así que el
    // seguimiento nuevo se sube sobre esa versión (sin ella, el servidor respondería que ya se sigue).
    final aSubir = actual?.estado == EstadoLocal.borrando && seguimiento.version == null
        ? seguimiento.copyWith(version: _leer(actual!).seguimiento.version)
        : seguimiento;
    await _escribir(aSubir, EstadoLocal.pendiente);
  }

  Future<void> dejarDeSeguir(int licitacionId) async {
    final fila = await _fila(licitacionId);
    if (fila == null) return;
    final seguimiento = _leer(fila).seguimiento;
    if (seguimiento.version == null) {
      // Nunca llegó al servidor: basta con borrarlo aquí.
      await (_db.delete(_tabla)..where((t) => t.licitacionId.equals(licitacionId))).go();
    } else {
      await _escribir(seguimiento, EstadoLocal.borrando);
    }
  }

  /// Sube los cambios pendientes, en el orden en que se hicieron. Se para al primer fallo de red o de sesión (lo que
  /// quede se subirá la próxima vez). Dos llamadas a la vez comparten la misma sincronización.
  Future<ResultadoDeSincronizacion> sincronizar() =>
      _sincronizando ??= _sincronizar().whenComplete(() => _sincronizando = null);

  Future<ResultadoDeSincronizacion> _sincronizar() async {
    final filas =
        await (_db.select(_tabla)
              ..where((t) => t.estado.isInValues([EstadoLocal.pendiente, EstadoLocal.borrando]))
              ..orderBy([(t) => OrderingTerm(expression: t.cambiadoEn)]))
            .get();
    var subidos = 0;
    var conflictos = 0;
    for (final fila in filas) {
      final local = _leer(fila);
      try {
        if (local.estado == EstadoLocal.borrando) {
          await _api.borrar(local.licitacionId);
          await (_db.delete(_tabla)..where((t) => t.licitacionId.equals(local.licitacionId))).go();
        } else {
          final guardado = await _api.guardar(local.seguimiento);
          await _trasSubir(fila, guardado);
        }
        subidos++;
      } on ConflictoDeVersion catch (c) {
        conflictos++;
        await _escribir(local.seguimiento, EstadoLocal.conflicto, delServidor: c.actual);
      } on DatosNoValidos catch (e) {
        // La app valida lo mismo que el servidor, así que no debería pasar; se deja pendiente y se avisa.
        debugPrint('El servidor no acepta el seguimiento ${local.licitacionId}: ${e.errores}');
        return (subidos: subidos, conflictos: conflictos, error: e);
      } on ErrorDeApi catch (e) {
        return (subidos: subidos, conflictos: conflictos, error: e);
      }
    }
    return (subidos: subidos, conflictos: conflictos, error: null);
  }

  /// Si se ha vuelto a cambiar mientras se subía, se conserva el cambio nuevo (sigue pendiente) pero ya sobre la
  /// versión recién guardada, para que la próxima subida no sea un conflicto consigo mismo.
  Future<void> _trasSubir(FilaDeSeguimiento subida, Seguimiento guardado) => _db.transaction(() async {
    final ahora = await _fila(guardado.licitacionId);
    if (ahora == null) return;
    if (ahora.cambiadoEn == subida.cambiadoEn) {
      await _escribir(guardado, EstadoLocal.sincronizado);
    } else if (ahora.estado == EstadoLocal.pendiente) {
      await _escribir(_leer(ahora).seguimiento.copyWith(version: guardado.version), EstadoLocal.pendiente);
    }
  });

  /// Trae los seguimientos del servidor (los cambiados en otro dispositivo). Lo que está pendiente aquí no se toca.
  Future<void> refrescar() async {
    final delServidor = await _api.todos();
    await _db.transaction(() async {
      final locales = {for (final f in await _db.select(_tabla).get()) f.licitacionId: f};
      for (final s in delServidor) {
        final local = locales[s.licitacionId];
        if (local == null || local.estado == EstadoLocal.sincronizado) {
          await _escribir(s, EstadoLocal.sincronizado);
        }
      }
      final ids = delServidor.map((s) => s.licitacionId).toSet();
      for (final local in locales.values) {
        if (local.estado == EstadoLocal.sincronizado && !ids.contains(local.licitacionId)) {
          await (_db.delete(_tabla)..where((t) => t.licitacionId.equals(local.licitacionId))).go();
        }
      }
    });
  }

  /// Resuelve un conflicto quedándose con lo de este móvil: se vuelve a subir sobre la versión del servidor.
  Future<void> quedarmeConLoMio(int licitacionId) async {
    final local = await _local(licitacionId);
    if (local == null || !local.enConflicto) return;
    await _escribir(local.seguimiento.copyWith(version: local.delServidor?.version), EstadoLocal.pendiente);
  }

  /// Resuelve un conflicto quedándose con lo del servidor (o dejándolo de seguir, si allí se borró).
  Future<void> usarLoDelServidor(int licitacionId) async {
    final local = await _local(licitacionId);
    if (local == null || !local.enConflicto) return;
    final delServidor = local.delServidor;
    if (delServidor == null) {
      await (_db.delete(_tabla)..where((t) => t.licitacionId.equals(licitacionId))).go();
    } else {
      await _escribir(delServidor, EstadoLocal.sincronizado);
    }
  }

  /// Al cerrar sesión: los seguimientos son de la cuenta, no del móvil.
  Future<void> borrarTodo() => _db.delete(_tabla).go();

  Future<FilaDeSeguimiento?> _fila(int licitacionId) =>
      (_db.select(_tabla)..where((t) => t.licitacionId.equals(licitacionId))).getSingleOrNull();

  Future<SeguimientoLocal?> _local(int licitacionId) async {
    final fila = await _fila(licitacionId);
    return fila == null ? null : _leer(fila);
  }

  Future<void> _escribir(Seguimiento s, EstadoLocal estado, {Seguimiento? delServidor}) => _db
      .into(_tabla)
      .insertOnConflictUpdate(
        SeguimientosLocalesCompanion.insert(
          licitacionId: Value(s.licitacionId),
          datos: jsonEncode(s.toJson()),
          estado: estado,
          delServidor: Value(delServidor == null ? null : jsonEncode(delServidor.toJson())),
          cambiadoEn: _reloj(),
        ),
      );

  SeguimientoLocal _leer(FilaDeSeguimiento fila) => SeguimientoLocal(
    Seguimiento.fromJson(jsonDecode(fila.datos) as Map<String, dynamic>),
    fila.estado,
    delServidor: fila.delServidor == null
        ? null
        : Seguimiento.fromJson(jsonDecode(fila.delServidor!) as Map<String, dynamic>),
  );

  static List<SeguimientoLocal> _ordenar(Iterable<SeguimientoLocal> lista) {
    final ordenada = lista.toList()
      ..sort((a, b) {
        final pa = a.seguimiento.resumen.plazo;
        final pb = b.seguimiento.resumen.plazo;
        if (pa != pb) {
          if (pa == null) return 1;
          if (pb == null) return -1;
          return pa.compareTo(pb);
        }
        return a.licitacionId.compareTo(b.licitacionId);
      });
    return ordenada;
  }
}
