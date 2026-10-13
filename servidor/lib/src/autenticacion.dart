import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

/// El token no sirve: falta, está mal firmado, ha caducado o es para otro emisor o audiencia. Siempre un 401.
class TokenNoValido implements Exception {
  TokenNoValido(this.motivo);

  final String motivo;

  @override
  String toString() => 'TokenNoValido: $motivo';
}

/// El usuario de la petición, sacado de su token.
class Usuario {
  const Usuario({required this.id, this.correo, this.nombre});

  /// El claim `sub` de Keycloak: estable aunque cambie el correo.
  final String id;
  final String? correo;
  final String? nombre;
}

/// Comprueba los tokens de acceso de Keycloak, los mismos que acepta la API del radar: firma RS256 con las claves
/// publicadas por el realm (JWKS), emisor, audiencia `radar-api` y caducidad.
///
/// Las claves se guardan en memoria una hora. Si llega un token firmado con una clave que no se conoce (Keycloak ha
/// rotado las claves), se vuelven a pedir, como mucho una vez por minuto para que un token falso no sirva para
/// saturar a Keycloak.
class VerificadorDeTokens {
  VerificadorDeTokens({
    required this.emisor,
    required this.audiencia,
    required this._cargarClaves,
    DateTime Function()? reloj,
    this.tolerancia = const Duration(seconds: 30),
  }) : _reloj = reloj ?? DateTime.now;

  /// Con las claves públicas del realm pedidas por HTTP (por la red interna en producción).
  factory VerificadorDeTokens.conJwks({
    required String emisor,
    required String audiencia,
    required Uri jwks,
    http.Client? cliente,
  }) {
    final http_ = cliente ?? http.Client();
    return VerificadorDeTokens(
      emisor: emisor,
      audiencia: audiencia,
      cargarClaves: () async {
        final respuesta = await http_.get(jwks).timeout(const Duration(seconds: 10));
        if (respuesta.statusCode != 200) {
          throw StateError('Keycloak ha respondido ${respuesta.statusCode} al pedir las claves');
        }
        return jsonDecode(respuesta.body) as Map<String, dynamic>;
      },
    );
  }

  final String emisor;
  final String audiencia;
  final Duration tolerancia;
  final Future<Map<String, dynamic>> Function() _cargarClaves;
  final DateTime Function() _reloj;

  late JsonWebKeyStore _claves;
  DateTime? _cargadasEn;
  DateTime? _ultimaRecarga;

  Future<Usuario> verificar(String? cabecera) async {
    if (cabecera == null || !cabecera.startsWith('Bearer ')) {
      throw TokenNoValido('Falta el token (cabecera Authorization: Bearer)');
    }
    final token = cabecera.substring('Bearer '.length).trim();
    JsonWebToken jwt;
    try {
      jwt = await _verificarFirma(token, recargar: false);
    } on TokenNoValido {
      // Puede ser una clave nueva: se recargan las claves (con límite) y se intenta una vez más.
      if (!_puedeRecargar()) rethrow;
      jwt = await _verificarFirma(token, recargar: true);
    }
    return _comprobarClaims(jwt.claims.toJson());
  }

  Future<JsonWebToken> _verificarFirma(String token, {required bool recargar}) async {
    final ahora = _reloj();
    final cargadasEn = _cargadasEn;
    if (recargar || cargadasEn == null || ahora.difference(cargadasEn) > const Duration(hours: 1)) {
      final jwks = await _cargarClaves();
      _claves = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(jwks));
      _cargadasEn = ahora;
      if (recargar) _ultimaRecarga = ahora;
    }
    try {
      return await JsonWebToken.decodeAndVerify(token, _claves, allowedArguments: const ['RS256']);
    } on Object {
      throw TokenNoValido('Firma no válida');
    }
  }

  bool _puedeRecargar() {
    final ultima = _ultimaRecarga;
    return ultima == null || _reloj().difference(ultima) > const Duration(minutes: 1);
  }

  Usuario _comprobarClaims(Map<String, dynamic> claims) {
    if (claims['iss'] != emisor) throw TokenNoValido('Emisor no esperado');
    final aud = claims['aud'];
    final audiencias = aud is List ? aud.cast<String>() : (aud is String ? [aud] : const <String>[]);
    if (!audiencias.contains(audiencia)) throw TokenNoValido('El token no es para esta API');
    final exp = claims['exp'];
    if (exp is! num) throw TokenNoValido('El token no caduca');
    final caducidad = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    if (_reloj().toUtc().isAfter(caducidad.add(tolerancia))) throw TokenNoValido('Token caducado');
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) throw TokenNoValido('El token no identifica al usuario');
    return Usuario(id: sub, correo: claims['email'] as String?, nombre: claims['name'] as String?);
  }
}
