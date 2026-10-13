import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'base_de_datos.g.dart';

/// En qué punto está la copia local de un seguimiento respecto al servidor.
enum EstadoLocal {
  /// Igual que en el servidor.
  sincronizado,

  /// Cambiado aquí, falta subirlo.
  pendiente,

  /// Se ha dejado de seguir aquí, falta borrarlo en el servidor.
  borrando,

  /// Al subirlo, el servidor tenía otra versión: hay que elegir cuál se queda.
  conflicto,
}

/// La copia local de los seguimientos: lo que enseña la app (funciona sin red) y, a la vez, la cola de cambios
/// pendientes. Cada fila guarda el último estado, no cada cambio: si se cambia tres veces sin red, se sube una.
@DataClassName('FilaDeSeguimiento')
class SeguimientosLocales extends Table {
  IntColumn get licitacionId => integer()();

  /// El seguimiento en JSON, con la versión del servidor sobre la que se ha editado.
  TextColumn get datos => text()();

  TextColumn get estado => textEnum<EstadoLocal>()();

  /// En un conflicto, lo que tiene el servidor (JSON), o nulo si allí se ha borrado.
  TextColumn get delServidor => text().nullable()();

  DateTimeColumn get cambiadoEn => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {licitacionId};
}

/// Pares clave-valor sueltos (por ejemplo, cuántos avisos del radar se han notificado ya).
class Ajustes extends Table {
  TextColumn get clave => text()();

  TextColumn get valor => text()();

  @override
  Set<Column<Object>> get primaryKey => {clave};
}

@DriftDatabase(tables: [SeguimientosLocales, Ajustes])
class BaseDeDatos extends _$BaseDeDatos {
  /// La app y la tarea en segundo plano comparten la misma conexión (un isolate de drift), así no se bloquean.
  BaseDeDatos([QueryExecutor? ejecutor])
    : super(
        ejecutor ?? driftDatabase(name: 'radar_movil', native: const DriftNativeOptions(shareAcrossIsolates: true)),
      );

  @override
  int get schemaVersion => 1;

  Future<String?> ajuste(String clave) async =>
      (await (select(ajustes)..where((a) => a.clave.equals(clave))).getSingleOrNull())?.valor;

  Future<void> fijarAjuste(String clave, String valor) =>
      into(ajustes).insertOnConflictUpdate(AjustesCompanion.insert(clave: clave, valor: valor));
}
