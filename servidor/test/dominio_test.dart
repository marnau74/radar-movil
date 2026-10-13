import 'package:servidor/servidor.dart';
import 'package:test/test.dart';

Map<String, dynamic> cambioValido() => {
  'resumen': {
    'titulo': 'Servicio de limpieza',
    'organo': 'Ayuntamiento de Ejemplo',
    'importe': 120000.5,
    'plazo': '2026-10-26T21:59:00Z',
  },
  'etapa': 'preparando',
  'notas': '  Revisar el pliego técnico  ',
  'responsable': 'Ana',
};

void main() {
  group('CambioDeSeguimiento.validar', () {
    test('acepta un cambio correcto y limpia los textos', () {
      final cambio = CambioDeSeguimiento.validar(cambioValido());
      expect(cambio.etapa, Etapa.preparando);
      expect(cambio.notas, 'Revisar el pliego técnico');
      expect(cambio.resumen.plazo, DateTime.utc(2026, 10, 26, 21, 59));
      expect(cambio.version, isNull);
    });

    test('reúne todos los errores a la vez', () {
      expect(
        () => CambioDeSeguimiento.validar({
          'resumen': {'titulo': '', 'organo': 'Órgano', 'importe': -3, 'plazo': 'mañana'},
          'etapa': 'ganadísima',
          'notas': 'x' * 5001,
          'version': 0,
        }),
        throwsA(
          isA<DatoNoValido>().having(
            (e) => e.errores.keys,
            'campos',
            containsAll(['resumen.titulo', 'resumen.importe', 'resumen.plazo', 'etapa', 'notas', 'version']),
          ),
        ),
      );
    });

    test('un cuerpo que no es un objeto se rechaza', () {
      expect(() => CambioDeSeguimiento.validar([1, 2]), throwsA(isA<DatoNoValido>()));
    });

    test('un responsable vacío es como no tenerlo', () {
      final cambio = CambioDeSeguimiento.validar({...cambioValido(), 'responsable': '   '});
      expect(cambio.responsable, isNull);
    });
  });

  group('Embudo', () {
    test('la tasa de éxito solo cuenta las resueltas', () {
      const embudo = Embudo({
        Etapa.preparando: (cuantas: 5, importe: 100),
        Etapa.ganada: (cuantas: 1, importe: 10),
        Etapa.perdida: (cuantas: 3, importe: 30),
      });
      expect(embudo.tasaDeExito, 0.25);
      expect(const Embudo({}).tasaDeExito, isNull);
    });

    test('incluye todas las etapas aunque estén vacías', () {
      final json = const Embudo({}).aJson();
      expect((json['etapas'] as List).length, Etapa.values.length);
    });
  });

  test('ganada, perdida y descartada cierran el seguimiento', () {
    expect(Etapa.values.where((e) => e.cerrada), [Etapa.ganada, Etapa.perdida, Etapa.descartada]);
  });
}
