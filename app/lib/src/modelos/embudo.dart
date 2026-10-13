import 'package:flutter/foundation.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';

/// Las cifras de una etapa.
typedef CifrasDeEtapa = ({int cuantas, double importe});

/// Las cifras del embudo, calculadas en el móvil con lo que hay en local: así cuadran con la lista aunque haya cambios
/// sin subir. (El servidor tiene `GET /embudo` con la misma cuenta hecha en MongoDB.)
@immutable
class Embudo {
  const Embudo(this.porEtapa);

  factory Embudo.de(List<SeguimientoLocal> seguimientos) {
    final cuentas = {for (final etapa in Etapa.values) etapa: (cuantas: 0, importe: 0.0)};
    for (final local in seguimientos) {
      final s = local.seguimiento;
      final antes = cuentas[s.etapa]!;
      cuentas[s.etapa] = (cuantas: antes.cuantas + 1, importe: antes.importe + (s.resumen.importe ?? 0));
    }
    return Embudo(cuentas);
  }

  final Map<Etapa, CifrasDeEtapa> porEtapa;

  CifrasDeEtapa cifras(Etapa etapa) => porEtapa[etapa] ?? (cuantas: 0, importe: 0);

  /// Lo que se puede ganar todavía: el importe de las que siguen abiertas.
  double get importeEnJuego => Etapa.values.where((e) => !e.cerrada).fold(0, (suma, e) => suma + cifras(e).importe);

  int get abiertas => Etapa.values.where((e) => !e.cerrada).fold(0, (suma, e) => suma + cifras(e).cuantas);

  /// Ganadas entre las resueltas (ganadas y perdidas; las descartadas no cuentan). Nula si no hay ninguna resuelta.
  double? get tasaDeExito {
    final ganadas = cifras(Etapa.ganada).cuantas;
    final resueltas = ganadas + cifras(Etapa.perdida).cuantas;
    return resueltas == 0 ? null : ganadas / resueltas;
  }
}
