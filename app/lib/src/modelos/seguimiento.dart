import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';

part 'seguimiento.freezed.dart';
part 'seguimiento.g.dart';

/// Las etapas de una oferta, las mismas que valida el servidor.
enum Etapa {
  interesa('Interesa'),
  preparando('Preparando la oferta'),
  presentada('Presentada'),
  ganada('Ganada'),
  perdida('Perdida'),
  descartada('Descartada');

  Etapa(this.nombre);

  final String nombre;

  /// El nombre en una palabra, para las listas y el selector de etapas.
  String get corto => this == preparando ? 'Preparando' : nombre;

  /// Ganada, perdida y descartada cierran el seguimiento: ya no hay plazos que avisar.
  bool get cerrada => this == ganada || this == perdida || this == descartada;
}

/// Lo que se guarda de la licitación junto al seguimiento, para que el embudo funcione sin el radar.
@freezed
abstract class ResumenDeLicitacion with _$ResumenDeLicitacion {
  const factory ResumenDeLicitacion({
    required String titulo,
    required String organo,
    String? expediente,
    double? importe,
    DateTime? plazo,
  }) = _ResumenDeLicitacion;

  factory ResumenDeLicitacion.fromJson(Map<String, dynamic> json) => _$ResumenDeLicitacionFromJson(json);

  factory ResumenDeLicitacion.deLaFicha(FichaDeLicitacion f) => ResumenDeLicitacion(
    titulo: f.titulo,
    organo: f.organo.nombre,
    expediente: f.expediente,
    importe: f.importeSinIva,
    plazo: f.plazoPresentacion?.toUtc(),
  );
}

@freezed
abstract class CambioDeEtapa with _$CambioDeEtapa {
  const factory CambioDeEtapa({required Etapa a, required DateTime en, Etapa? de}) = _CambioDeEtapa;

  factory CambioDeEtapa.fromJson(Map<String, dynamic> json) => _$CambioDeEtapaFromJson(json);
}

/// Un seguimiento tal como lo devuelve el servidor. `version` es nula mientras no se ha subido nunca.
@freezed
abstract class Seguimiento with _$Seguimiento {
  const factory Seguimiento({
    required int licitacionId,
    required ResumenDeLicitacion resumen,
    required Etapa etapa,
    @Default('') String notas,
    String? responsable,
    DateTime? fechaInterna,
    @Default([]) List<CambioDeEtapa> historial,
    int? version,
    DateTime? actualizadoEn,
  }) = _Seguimiento;

  const Seguimiento._();

  factory Seguimiento.fromJson(Map<String, dynamic> json) => _$SeguimientoFromJson(json);

  /// Un seguimiento nuevo, aún sin subir.
  factory Seguimiento.nuevo(int licitacionId, ResumenDeLicitacion resumen, DateTime ahora) => Seguimiento(
    licitacionId: licitacionId,
    resumen: resumen,
    etapa: Etapa.interesa,
    historial: [CambioDeEtapa(a: Etapa.interesa, en: ahora.toUtc())],
  );

  /// El cuerpo del `PUT`: lo editable y la versión sobre la que se ha editado.
  Map<String, dynamic> cuerpoDelCambio() => {
    'resumen': resumen.toJson(),
    'etapa': etapa.name,
    'notas': notas,
    'responsable': responsable,
    'fechaInterna': fechaInterna?.toUtc().toIso8601String(),
    'version': ?version,
  };

  /// Pasa a otra etapa apuntándolo en el historial (el servidor lo vuelve a apuntar al sincronizar).
  Seguimiento conEtapa(Etapa nueva, DateTime ahora) => nueva == etapa
      ? this
      : copyWith(
          etapa: nueva,
          historial: [
            ...historial,
            CambioDeEtapa(de: etapa, a: nueva, en: ahora.toUtc()),
          ],
        );
}
