import 'dart:io';
import 'dart:math';

import 'package:jose/jose.dart';
import 'package:mongo_dart/mongo_dart.dart';

const emisor = 'http://localhost:8088/auth/realms/radar';
const audiencia = 'radar-api';

/// Una clave RSA de prueba, como las que publica Keycloak en su JWKS.
JsonWebKey claveDePrueba(String kid) {
  final clave = Map<String, dynamic>.of(JsonWebKey.generate('RS256', keyBitLength: 2048).toJson())..['kid'] = kid;
  return JsonWebKey.fromJson(clave);
}

Map<String, dynamic> jwks(List<JsonWebKey> claves) => {'keys': claves.map((c) => c.toJson()).toList()};

/// Un token firmado como lo firmaría Keycloak; cada campo se puede cambiar para probar los casos malos.
String token(
  JsonWebKey clave, {
  String sub = 'usuario-ana',
  String iss = emisor,
  Object aud = audiencia,
  DateTime? caduca,
  String? correo = 'ana@demo.example',
}) {
  final exp = (caduca ?? DateTime.now().add(const Duration(minutes: 5))).millisecondsSinceEpoch ~/ 1000;
  final constructor = JsonWebSignatureBuilder()
    ..jsonContent = {'sub': sub, 'iss': iss, 'aud': aud, 'exp': exp, 'email': ?correo}
    ..addRecipient(clave, algorithm: 'RS256');
  return constructor.build().toCompactSerialization();
}

/// Una base de MongoDB propia para cada archivo de pruebas, en el MongoDB de `RADAR_MOVIL_MONGO_PRUEBAS`
/// (por defecto, el del compose de desarrollo).
Future<Db> baseDePruebas() async {
  final servidor = Platform.environment['RADAR_MOVIL_MONGO_PRUEBAS'] ?? 'mongodb://localhost:27019';
  final nombre = 'pruebas_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
  final db = await Db.create('$servidor/$nombre');
  await db.open();
  return db;
}
