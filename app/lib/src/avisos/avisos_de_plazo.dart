import 'package:flutter/foundation.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';

/// Cuándo se avisa de un plazo.
enum TipoDeAviso {
  tresDias(Duration(hours: 72), 'Cierra en 3 días'),
  unDia(Duration(hours: 24), 'Cierra mañana'),
  fechaInterna(Duration.zero, 'Hoy es tu fecha límite interna');

  TipoDeAviso(this.antelacion, this.titulo);

  final Duration antelacion;
  final String titulo;
}

/// Un aviso que hay que tener programado en el móvil.
@immutable
class AvisoProgramado {
  const AvisoProgramado({
    required this.id,
    required this.licitacionId,
    required this.tipo,
    required this.cuando,
    required this.titulo,
    required this.texto,
  });

  /// Estable por licitación y tipo: volver a programar el mismo aviso lo sustituye en vez de duplicarlo.
  final int id;
  final int licitacionId;
  final TipoDeAviso tipo;
  final DateTime cuando;
  final String titulo;
  final String texto;

  /// Lo que abre al tocar el aviso: la ficha de la licitación.
  String get ruta => '/licitaciones/$licitacionId';

  @override
  bool operator ==(Object other) =>
      other is AvisoProgramado && other.id == id && other.cuando == cuando && other.texto == texto;

  @override
  int get hashCode => Object.hash(id, cuando, texto);
}

/// El identificador del aviso de una licitación: cabe en los 31 bits que admite Android.
int idDeAviso(int licitacionId, TipoDeAviso tipo) => (licitacionId % 500000000) * 4 + tipo.index + 1;

/// El identificador del aviso que resume lo que han encontrado las alertas del radar.
const idDeAvisoDeAlertas = 0;

/// Los avisos de los seguimientos abiertos: 72 y 24 horas antes de que cierre el plazo de presentación y, si se ha
/// puesto, a las 9:00 del día de la fecha límite interna. Solo los que aún no han pasado.
List<AvisoProgramado> avisosDePlazo(List<SeguimientoLocal> seguimientos, DateTime ahora) {
  final avisos = <AvisoProgramado>[];
  for (final local in seguimientos) {
    final s = local.seguimiento;
    if (s.etapa.cerrada) continue;
    final plazo = s.resumen.plazo;
    if (plazo != null) {
      for (final tipo in [TipoDeAviso.tresDias, TipoDeAviso.unDia]) {
        final cuando = plazo.subtract(tipo.antelacion);
        if (cuando.isAfter(ahora)) {
          avisos.add(
            AvisoProgramado(
              id: idDeAviso(s.licitacionId, tipo),
              licitacionId: s.licitacionId,
              tipo: tipo,
              cuando: cuando,
              titulo: tipo.titulo,
              texto: s.resumen.titulo,
            ),
          );
        }
      }
    }
    final interna = s.fechaInterna?.toLocal();
    if (interna != null) {
      final cuando = DateTime(interna.year, interna.month, interna.day, 9);
      if (cuando.isAfter(ahora)) {
        avisos.add(
          AvisoProgramado(
            id: idDeAviso(s.licitacionId, TipoDeAviso.fechaInterna),
            licitacionId: s.licitacionId,
            tipo: TipoDeAviso.fechaInterna,
            cuando: cuando,
            titulo: TipoDeAviso.fechaInterna.titulo,
            texto: s.resumen.titulo,
          ),
        );
      }
    }
  }
  return avisos;
}
