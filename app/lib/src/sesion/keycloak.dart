import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:radar_movil/src/configuracion.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

/// Inicio de sesión en Keycloak con AppAuth: el navegador del sistema (Custom Tabs), código de autorización y PKCE.
/// La app es un cliente público: no lleva ningún secreto.
class KeycloakConAppAuth implements ProveedorDeIdentidad {
  KeycloakConAppAuth(this._configuracion, {FlutterAppAuth? appAuth}) : _appAuth = appAuth ?? const FlutterAppAuth();

  final Configuracion _configuracion;
  final FlutterAppAuth _appAuth;

  // En local Keycloak va por HTTP; en producción el emisor es HTTPS y esto queda desactivado solo.
  bool get _inseguro => _configuracion.emisor.startsWith('http://');

  @override
  Future<Tokens> iniciarSesion() async {
    try {
      final respuesta = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _configuracion.cliente,
          _configuracion.redireccion,
          issuer: _configuracion.emisor,
          // offline_access: la sesión dura aunque no se abra la app en días (la del navegador caduca en una hora).
          scopes: const ['openid', 'profile', 'email', 'offline_access'],
          allowInsecureConnections: _inseguro,
        ),
      );
      return _tokens(respuesta);
    } on FlutterAppAuthUserCancelledException {
      throw const InicioCancelado();
    }
  }

  @override
  Future<Tokens> refrescar(String refresco) async {
    try {
      final respuesta = await _appAuth.token(
        TokenRequest(
          _configuracion.cliente,
          _configuracion.redireccion,
          issuer: _configuracion.emisor,
          refreshToken: refresco,
          allowInsecureConnections: _inseguro,
        ),
      );
      return _tokens(respuesta, refrescoAnterior: refresco);
    } on FlutterAppAuthPlatformException catch (e) {
      if (e.platformErrorDetails.error == 'invalid_grant') throw const RefrescoRechazado();
      rethrow;
    }
  }

  @override
  Future<void> cerrarSesion(Tokens tokens) async {
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: tokens.idToken,
        postLogoutRedirectUrl: _configuracion.redireccion,
        issuer: _configuracion.emisor,
        allowInsecureConnections: _inseguro,
      ),
    );
  }

  Tokens _tokens(TokenResponse r, {String? refrescoAnterior}) => Tokens(
    acceso: r.accessToken!,
    refresco: r.refreshToken ?? refrescoAnterior,
    idToken: r.idToken,
    caducaEn: r.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 5)),
  );
}

/// Los tokens cifrados con el Keystore de Android. Nunca en `SharedPreferences`, que es texto plano.
class AlmacenSeguro implements AlmacenDeTokens {
  AlmacenSeguro([FlutterSecureStorage? almacen]) : _almacen = almacen ?? const FlutterSecureStorage();

  static const _clave = 'radar_movil.tokens';

  final FlutterSecureStorage _almacen;

  @override
  Future<Tokens?> leer() async {
    final texto = await _almacen.read(key: _clave);
    return texto == null ? null : Tokens.desdeJson(jsonDecode(texto) as Map<String, dynamic>);
  }

  @override
  Future<void> guardar(Tokens tokens) => _almacen.write(key: _clave, value: jsonEncode(tokens.aJson()));

  @override
  Future<void> borrar() => _almacen.delete(key: _clave);
}
