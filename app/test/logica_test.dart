import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radar_movil/src/avisos/avisos_de_plazo.dart';
import 'package:radar_movil/src/datos/base_de_datos.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/modelos/embudo.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/ui/formato.dart';

import 'ayudas.dart';

SeguimientoLocal _local(Seguimiento s) => SeguimientoLocal(s, EstadoLocal.sincronizado);

void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  group('modelos con respuestas reales del radar', () {
    test('la búsqueda', () {
      final pagina = PaginaDeLicitaciones.fromJson(datos('busqueda.json'));
      expect(pagina.elementos, hasLength(3));
      expect(pagina.hayMas, isTrue);
      expect(
        pagina.elementos.first.plazoPresentacion,
        isNull,
        reason: 'las que no publican plazo también admiten ofertas',
      );
      expect(pagina.elementos.last.plazoPresentacion, DateTime.utc(2026, 10, 19, 21, 59));
    });

    test('la ficha con lotes y documentos', () {
      final ficha = FichaDeLicitacion.fromJson(datos('ficha.json'));
      expect(ficha.organo.nombre, contains('Instituto Social de la Marina'));
      expect(ficha.lotes, hasLength(3));
      expect(ficha.documentos.first.descripcion, 'Pliego de cláusulas administrativas');
      final resumen = ResumenDeLicitacion.deLaFicha(ficha);
      expect(resumen.importe, 47775);
      expect(resumen.plazo!.isUtc, isTrue);
    });

    test('la ficha adjudicada, sin plazo', () {
      final ficha = FichaDeLicitacion.fromJson(datos('ficha-adjudicada.json'));
      expect(ficha.plazoPresentacion, isNull);
      expect(ficha.resultados.single.adjudicatario, isNotEmpty);
    });

    test('el cuerpo del PUT lleva la versión solo si la hay', () {
      expect(seguimiento(1).cuerpoDelCambio().containsKey('version'), isFalse);
      expect(seguimiento(1, version: 3).cuerpoDelCambio()['version'], 3);
    });

    test('cambiar de etapa lo apunta en el historial; a la misma etapa, no', () {
      final ahora = DateTime.utc(2026, 10, 13);
      final s = Seguimiento.nuevo(1, seguimiento(1).resumen, ahora);
      expect(s.conEtapa(Etapa.interesa, ahora), same(s));
      final cambiado = s.conEtapa(Etapa.preparando, ahora);
      expect(cambiado.historial.last.de, Etapa.interesa);
      expect(cambiado.historial.last.a, Etapa.preparando);
    });
  });

  group('errores de la API (RFC 9457)', () {
    DioException respuesta(int estado, Object? cuerpo) {
      final opciones = RequestOptions(path: '/seguimientos/1');
      return DioException(
        requestOptions: opciones,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: opciones, statusCode: estado, data: cuerpo),
      );
    }

    test('409 trae la versión guardada', () {
      final error = traducirError(
        respuesta(409, {'detail': 'Cambiado', 'actual': seguimiento(1, version: 4).toJson()}),
      );
      expect(error, isA<ConflictoDeVersion>().having((e) => e.actual?.version, 'versión', 4));
    });

    test('400 trae los campos', () {
      final error = traducirError(
        respuesta(400, {
          'detail': 'Hay campos con valores no válidos',
          'errores': [
            {'campo': 'notas', 'mensaje': 'Demasiado largas'},
          ],
        }),
      );
      expect(error, isA<DatosNoValidos>().having((e) => e.errores, 'errores', {'notas': 'Demasiado largas'}));
    });

    test('401, 404, 5xx y sin red', () {
      expect(traducirError(respuesta(401, null)), isA<SesionCaducada>());
      expect(traducirError(respuesta(404, {'detail': 'No existe'})).mensaje, 'No existe');
      expect(traducirError(respuesta(503, 'html de un proxy')), isA<ErrorDelServidor>());
      expect(
        traducirError(DioException.connectionError(requestOptions: RequestOptions(), reason: 'x')),
        isA<SinConexion>(),
      );
    });
  });

  group('avisos de plazo', () {
    final ahora = DateTime.utc(2026, 10, 13, 10);

    test('72 y 24 horas antes, con identificador estable', () {
      final avisos = avisosDePlazo([_local(seguimiento(20622372, plazo: DateTime.utc(2026, 10, 20, 22)))], ahora);
      expect(avisos.map((a) => a.tipo), [TipoDeAviso.tresDias, TipoDeAviso.unDia]);
      expect(avisos.first.cuando, DateTime.utc(2026, 10, 17, 22));
      expect(avisos.first.ruta, '/licitaciones/20622372');
      expect(avisos.map((a) => a.id).toSet(), hasLength(2));
      expect(avisosDePlazo([_local(seguimiento(20622372, plazo: DateTime.utc(2026, 10, 20, 22)))], ahora), avisos);
    });

    test('lo que ya ha pasado no se avisa', () {
      final avisos = avisosDePlazo([_local(seguimiento(1, plazo: DateTime.utc(2026, 10, 14, 20)))], ahora);
      expect(avisos.map((a) => a.tipo), [TipoDeAviso.unDia]);
    });

    test('las cerradas no avisan', () {
      final plazo = DateTime.utc(2026, 11);
      expect(avisosDePlazo([_local(seguimiento(1, etapa: Etapa.ganada, plazo: plazo))], ahora), isEmpty);
    });

    test('la fecha interna avisa a las 9:00 de ese día', () {
      final s = seguimiento(1).copyWith(fechaInterna: DateTime(2026, 10, 30, 12).toUtc());
      final interno = avisosDePlazo([_local(s)], ahora).singleWhere((a) => a.tipo == TipoDeAviso.fechaInterna);
      expect(interno.cuando, DateTime(2026, 10, 30, 9));
    });

    test('los identificadores caben en 31 bits y no se pisan entre licitaciones', () {
      final ids = {
        for (final id in [1, 2, 20622372, 999999999])
          for (final tipo in TipoDeAviso.values) idDeAviso(id, tipo),
      };
      expect(ids, hasLength(4 * TipoDeAviso.values.length));
      expect(ids.every((id) => id > idDeAvisoDeAlertas && id < 1 << 31), isTrue);
    });
  });

  group('embudo', () {
    test('cifras por etapa, importe en juego y tasa de éxito', () {
      final embudo = Embudo.de([
        _local(seguimiento(1, importe: 1000)),
        _local(seguimiento(2, etapa: Etapa.preparando, importe: 2000)),
        _local(seguimiento(3, etapa: Etapa.ganada, importe: 5000)),
        _local(seguimiento(4, etapa: Etapa.perdida, importe: 7000)),
        _local(seguimiento(5, etapa: Etapa.perdida, importe: null)),
        _local(seguimiento(6, etapa: Etapa.descartada)),
      ]);
      expect(embudo.abiertas, 2);
      expect(embudo.importeEnJuego, 3000);
      expect(embudo.cifras(Etapa.perdida), (cuantas: 2, importe: 7000.0));
      expect(embudo.tasaDeExito, closeTo(1 / 3, 1e-9));
      expect(Embudo.de(const []).tasaDeExito, isNull);
    });
  });

  group('formato', () {
    test('euros con y sin céntimos', () {
      // intl separa el símbolo con un espacio duro, para que no se parta la línea.
      expect(euros(47775), '47.775 €');
      expect(euros(47120.52), '47.120,52 €');
      expect(euros(null), 'Sin importe');
    });

    test('lo que queda de plazo', () {
      final ahora = DateTime(2026, 10, 13, 10);
      expect(plazoRestante(DateTime(2026, 10, 13, 9), ahora).urgencia, Urgencia.cerrado);
      expect(plazoRestante(DateTime(2026, 10, 13, 23, 59), ahora).texto, 'Cierra hoy a las 23:59');
      expect(plazoRestante(DateTime(2026, 10, 14, 14), ahora).texto, 'Cierra mañana a las 14:00');
      expect(plazoRestante(DateTime(2026, 10, 16, 14), ahora).texto, 'Cierra en 3 días');
      expect(plazoRestante(DateTime(2026, 10, 30, 14), ahora).urgencia, Urgencia.holgado);
      expect(plazoRestante(null, ahora), (texto: 'Sin plazo publicado', urgencia: Urgencia.sinPlazo));
    });

    test('el cambio de hora de octubre no se come un día', () {
      // El 25 de octubre de 2026 se atrasa la hora en España.
      final ahora = DateTime(2026, 10, 24, 22);
      expect(plazoRestante(DateTime(2026, 10, 26, 10), ahora).texto, 'Cierra en 2 días');
    });
  });
}
