import 'package:flutter_test/flutter_test.dart';
import 'package:radar_movil/src/sesion/sesion.dart';

import 'ayudas.dart';

void main() {
  late DateTime ahora;
  late ProveedorFalso proveedor;
  late AlmacenEnMemoria almacen;
  late Sesion sesion;

  setUp(() {
    ahora = DateTime(2026, 10, 13, 10);
    proveedor = ProveedorFalso(() => ahora);
    almacen = AlmacenEnMemoria();
    sesion = Sesion(proveedor, almacen, reloj: () => ahora);
  });

  test('iniciar guarda los tokens y saca el usuario del token', () async {
    final usuario = await sesion.iniciar();
    expect(usuario.id, 'usuario-ana');
    expect(usuario.visible, 'Ana Demo');
    expect(almacen.tokens, isNotNull);
  });

  test('cargar recupera la sesión guardada; un almacén dañado se borra', () async {
    await sesion.iniciar();
    expect((await Sesion(proveedor, almacen).cargar())?.id, 'usuario-ana');

    almacen.roto = true;
    expect(await Sesion(proveedor, almacen).cargar(), isNull);
  });

  test('un token vigente no se refresca', () async {
    await sesion.iniciar();
    expect(await sesion.token(), isNotNull);
    expect(proveedor.refrescos, 0);
  });

  test('a punto de caducar, se refresca antes de usarlo', () async {
    await sesion.iniciar();
    ahora = ahora.add(const Duration(minutes: 4, seconds: 40));
    await sesion.token();
    expect(proveedor.refrescos, 1);
  });

  test('varias peticiones a la vez refrescan una sola vez', () async {
    await sesion.iniciar();
    ahora = ahora.add(const Duration(minutes: 10));
    final tokens = await Future.wait([sesion.token(), sesion.token(), sesion.token()]);
    expect(proveedor.refrescos, 1);
    expect(tokens.toSet(), hasLength(1));
  });

  test('si Keycloak rechaza el refresco, se cierra la sesión y se avisa', () async {
    await sesion.iniciar();
    final cambios = <Usuario?>[];
    sesion.cambios.listen(cambios.add);
    proveedor.rechazarRefresco = true;
    expect(await sesion.token(forzar: true), isNull);
    expect(sesion.usuario, isNull);
    expect(almacen.tokens, isNull);
    await pumpEventQueue();
    expect(cambios, [null]);
  });

  test('sin red, el refresco falla pero la sesión sigue', () async {
    await sesion.iniciar();
    proveedor.sinRed = true;
    await expectLater(sesion.token(forzar: true), throwsA(anything));
    expect(sesion.usuario, isNotNull);
  });

  test('cerrar sesión borra los tokens aunque Keycloak no responda', () async {
    await sesion.iniciar();
    proveedor.sinRed = true;
    await sesion.cerrar();
    expect(sesion.usuario, isNull);
    expect(almacen.tokens, isNull);
    expect(proveedor.cierres, 1);
  });

  test('cancelar el inicio de sesión no deja sesión', () async {
    proveedor.cancelar = true;
    await expectLater(sesion.iniciar(), throwsA(isA<InicioCancelado>()));
    expect(sesion.usuario, isNull);
  });
}
