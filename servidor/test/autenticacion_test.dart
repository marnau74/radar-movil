import 'package:servidor/servidor.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

void main() {
  final clave = claveDePrueba('clave-1');
  final otra = claveDePrueba('clave-2');
  late int cargas;
  late List<Map<String, dynamic>> publicadas;
  late DateTime ahora;

  VerificadorDeTokens verificador() => VerificadorDeTokens(
    emisor: emisor,
    audiencia: audiencia,
    cargarClaves: () async {
      cargas++;
      return publicadas.removeAt(0);
    },
    reloj: () => ahora,
  );

  setUp(() {
    cargas = 0;
    publicadas = [
      jwks([clave]),
      jwks([clave, otra]),
      jwks([clave, otra]),
    ];
    ahora = DateTime.now();
  });

  test('acepta un token bueno y saca el usuario', () async {
    final usuario = await verificador().verificar('Bearer ${token(clave)}');
    expect(usuario.id, 'usuario-ana');
    expect(usuario.correo, 'ana@demo.example');
  });

  test('la audiencia puede venir como lista', () async {
    final usuario = await verificador().verificar('Bearer ${token(clave, aud: ['account', audiencia])}');
    expect(usuario.id, 'usuario-ana');
  });

  for (final (caso, cabecera) in [
    ('sin cabecera', null),
    ('sin Bearer', 'Basic abc'),
    ('emisor de otro realm', 'Bearer ${token(clave, iss: 'http://localhost:8088/auth/realms/otro')}'),
    ('para otra API', 'Bearer ${token(clave, aud: 'otra-api')}'),
    ('caducado', 'Bearer ${token(clave, caduca: DateTime.now().subtract(const Duration(minutes: 5)))}'),
    ('sin usuario', 'Bearer ${token(clave, sub: '')}'),
    ('basura', 'Bearer esto.no.es'),
  ]) {
    test('rechaza un token $caso', () {
      expect(verificador().verificar(cabecera), throwsA(isA<TokenNoValido>()));
    });
  }

  test('rechaza un token firmado con una clave que no es del realm', () async {
    final ajena = claveDePrueba('clave-1');
    publicadas = [
      jwks([clave]),
      jwks([clave]),
    ];
    await expectLater(verificador().verificar('Bearer ${token(ajena)}'), throwsA(isA<TokenNoValido>()));
  });

  test('si Keycloak rota las claves, las vuelve a pedir una vez', () async {
    final v = verificador();
    await v.verificar('Bearer ${token(clave)}');
    expect(cargas, 1);
    final usuario = await v.verificar('Bearer ${token(otra)}');
    expect(usuario.id, 'usuario-ana');
    expect(cargas, 2);
  });

  test('no recarga las claves más de una vez por minuto', () async {
    final v = verificador();
    final desconocida = claveDePrueba('nunca-publicada');
    await expectLater(v.verificar('Bearer ${token(desconocida)}'), throwsA(isA<TokenNoValido>()));
    expect(cargas, 2);
    await expectLater(v.verificar('Bearer ${token(desconocida)}'), throwsA(isA<TokenNoValido>()));
    expect(cargas, 2, reason: 'un token falso repetido no debe martillear a Keycloak');
  });
}
