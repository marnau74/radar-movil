import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Los tokens de una sesión de Keycloak.
@immutable
class Tokens {
  const Tokens({required this.acceso, required this.caducaEn, this.refresco, this.idToken});

  factory Tokens.desdeJson(Map<String, dynamic> json) => Tokens(
    acceso: json['acceso'] as String,
    refresco: json['refresco'] as String?,
    idToken: json['idToken'] as String?,
    caducaEn: DateTime.parse(json['caducaEn'] as String),
  );

  final String acceso;
  final String? refresco;
  final String? idToken;
  final DateTime caducaEn;

  Map<String, dynamic> aJson() => {
    'acceso': acceso,
    'refresco': refresco,
    'idToken': idToken,
    'caducaEn': caducaEn.toUtc().toIso8601String(),
  };
}

/// Quién ha iniciado sesión, sacado del token de acceso. La app no verifica la firma: eso lo hacen las APIs.
@immutable
class Usuario {
  const Usuario({required this.id, this.correo, this.nombre});

  factory Usuario.delToken(String jwt) {
    final partes = jwt.split('.');
    if (partes.length != 3) throw const FormatException('El token no es un JWT');
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
    return Usuario(id: claims['sub'] as String, correo: claims['email'] as String?, nombre: claims['name'] as String?);
  }

  final String id;
  final String? correo;
  final String? nombre;

  String get visible => nombre ?? correo ?? 'Tu cuenta';

  @override
  bool operator ==(Object other) => other is Usuario && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Keycloak ya no acepta el token de refresco (sesión cerrada en el servidor o caducada): hay que volver a entrar.
class RefrescoRechazado implements Exception {
  const RefrescoRechazado();
}

/// El usuario ha cerrado el navegador sin iniciar sesión. No es un error que haya que enseñar.
class InicioCancelado implements Exception {
  const InicioCancelado();
}

/// Inicio de sesión con el navegador del sistema (código + PKCE). Se implementa con AppAuth; en las pruebas, con un
/// doble.
abstract interface class ProveedorDeIdentidad {
  /// Lanza [InicioCancelado] si el usuario vuelve atrás sin entrar.
  Future<Tokens> iniciarSesion();

  /// Lanza [RefrescoRechazado] si Keycloak no lo acepta; cualquier otro error es de red y no cierra la sesión.
  Future<Tokens> refrescar(String refresco);

  Future<void> cerrarSesion(Tokens tokens);
}

/// Donde se guardan los tokens entre arranques. En el móvil, cifrado (Keystore de Android).
abstract interface class AlmacenDeTokens {
  Future<Tokens?> leer();

  Future<void> guardar(Tokens tokens);

  Future<void> borrar();
}

/// La sesión: da un token de acceso válido a quien lo pida, refrescándolo cuando está a punto de caducar.
///
/// Se usa igual desde la app y desde la tarea en segundo plano, por eso no depende de Riverpod ni de Flutter.
class Sesion {
  Sesion(this._proveedor, this._almacen, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  /// Margen para refrescar antes de que caduque: un token que caduca durante la petición daría un 401.
  static const margen = Duration(seconds: 30);

  final ProveedorDeIdentidad _proveedor;
  final AlmacenDeTokens _almacen;
  final DateTime Function() _reloj;
  final _cambios = StreamController<Usuario?>.broadcast();

  Tokens? _tokens;
  Future<Tokens?>? _refrescoEnCurso;

  Usuario? get usuario => _tokens == null ? null : Usuario.delToken(_tokens!.acceso);

  Stream<Usuario?> get cambios => _cambios.stream;

  /// Lee la sesión guardada. Si el almacén está dañado (pasa al restaurar una copia en otro móvil), se empieza sin
  /// sesión.
  Future<Usuario?> cargar() async {
    try {
      _tokens = await _almacen.leer();
    } on Object {
      await _almacen.borrar();
      _tokens = null;
    }
    return usuario;
  }

  Future<Usuario> iniciar() async {
    final tokens = await _proveedor.iniciarSesion();
    await _fijar(tokens);
    return usuario!;
  }

  Future<void> cerrar() async {
    final tokens = _tokens;
    await _fijar(null);
    if (tokens != null) {
      // Se cierra también en Keycloak, pero la sesión local se cierra aunque eso falle (sin red, por ejemplo).
      try {
        await _proveedor.cerrarSesion(tokens);
      } on Object catch (error) {
        debugPrint('No se ha podido cerrar la sesión en Keycloak: $error');
      }
    }
  }

  /// Un token de acceso válido, o nulo si no hay sesión. Con [forzar] se refresca aunque no haya caducado (después de
  /// un 401). Varios refrescos a la vez se juntan en uno: Keycloak invalida el token de refresco al usarlo.
  Future<String?> token({bool forzar = false}) async {
    final tokens = _tokens;
    if (tokens == null) return null;
    if (!forzar && _reloj().add(margen).isBefore(tokens.caducaEn)) return tokens.acceso;
    final refrescado = await (_refrescoEnCurso ??= _refrescar(tokens).whenComplete(() => _refrescoEnCurso = null));
    return refrescado?.acceso;
  }

  Future<Tokens?> _refrescar(Tokens tokens) async {
    final refresco = tokens.refresco;
    if (refresco == null) {
      await _fijar(null);
      return null;
    }
    try {
      final nuevos = await _proveedor.refrescar(refresco);
      await _fijar(nuevos);
      return nuevos;
    } on RefrescoRechazado {
      await _fijar(null);
      return null;
    }
  }

  Future<void> _fijar(Tokens? tokens) async {
    final antes = usuario;
    _tokens = tokens;
    if (tokens == null) {
      await _almacen.borrar();
    } else {
      await _almacen.guardar(tokens);
    }
    if (usuario != antes) _cambios.add(usuario);
  }

  Future<void> dispose() => _cambios.close();
}
