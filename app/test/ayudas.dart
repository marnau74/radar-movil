import 'dart:convert';
import 'dart:io';

import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

/// Una respuesta real del radar guardada en `test/datos`.
Map<String, dynamic> datos(String nombre) =>
    jsonDecode(File('test/datos/$nombre').readAsStringSync()) as Map<String, dynamic>;

/// Un JWT sin firma válida (la app no la comprueba): solo importan los claims.
String jwt({String sub = 'usuario-ana', String? correo = 'ana@demo.example', String? nombre = 'Ana Demo'}) {
  String parte(Map<String, dynamic> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${parte({'alg': 'RS256'})}.${parte({'sub': sub, 'email': ?correo, 'name': ?nombre})}.firma';
}

class AlmacenEnMemoria implements AlmacenDeTokens {
  Tokens? tokens;
  bool roto = false;

  @override
  Future<Tokens?> leer() async {
    if (roto) throw const FormatException('Almacén dañado');
    return tokens;
  }

  @override
  Future<void> guardar(Tokens tokens) async => this.tokens = tokens;

  @override
  Future<void> borrar() async => tokens = null;
}

class ProveedorFalso implements ProveedorDeIdentidad {
  ProveedorFalso(this.reloj);

  final DateTime Function() reloj;
  int refrescos = 0;
  int cierres = 0;
  bool rechazarRefresco = false;

  /// Como Keycloak con la rotación de tokens de refresco: cada uno sirve una sola vez.
  bool unSoloUso = false;
  final _usados = <String>{};
  bool sinRed = false;
  bool cancelar = false;

  Tokens tokens(String sub) => Tokens(
    acceso: jwt(sub: sub),
    refresco: 'refresco-$sub-$refrescos',
    idToken: 'id',
    caducaEn: reloj().add(const Duration(minutes: 5)),
  );

  @override
  Future<Tokens> iniciarSesion() async {
    if (cancelar) throw const InicioCancelado();
    return tokens('usuario-ana');
  }

  @override
  Future<Tokens> refrescar(String refresco) async {
    // Como en la vida real, el refresco tarda: así se ve si dos peticiones a la vez refrescan dos veces.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (sinRed) throw const SocketException('Sin red');
    if (rechazarRefresco) throw const RefrescoRechazado();
    if (unSoloUso && !_usados.add(refresco)) throw const RefrescoRechazado();
    refrescos++;
    return tokens('usuario-ana');
  }

  @override
  Future<void> cerrarSesion(Tokens tokens) async {
    cierres++;
    if (sinRed) throw const SocketException('Sin red');
  }
}

/// Un seguimiento de prueba.
Seguimiento seguimiento(
  int id, {
  Etapa etapa = Etapa.interesa,
  int? version,
  double? importe = 10000,
  DateTime? plazo,
  String notas = '',
}) => Seguimiento(
  licitacionId: id,
  resumen: ResumenDeLicitacion(
    titulo: 'Licitación $id',
    organo: 'Ayuntamiento de Ejemplo',
    importe: importe,
    plazo: plazo ?? DateTime.utc(2026, 11, 20, 13),
  ),
  etapa: etapa,
  notas: notas,
  version: version,
);
