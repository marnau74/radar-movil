import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:radar_movil/src/ui/pantalla_avisos.dart';
import 'package:radar_movil/src/ui/pantalla_buscar.dart';
import 'package:radar_movil/src/ui/pantalla_editor.dart';
import 'package:radar_movil/src/ui/pantalla_ficha.dart';
import 'package:radar_movil/src/ui/pantalla_seguimiento.dart';

part 'rutas.g.dart';

final claveRaiz = GlobalKey<NavigatorState>(debugLabel: 'raiz');

/// Las tres secciones con su barra inferior; cada una conserva su pila y su posición al cambiar de sección.
@TypedStatefulShellRoute<RutaPrincipal>(
  branches: [
    TypedStatefulShellBranch<RamaBuscar>(routes: [TypedGoRoute<RutaBuscar>(path: '/')]),
    TypedStatefulShellBranch<RamaSeguimiento>(routes: [TypedGoRoute<RutaSeguimiento>(path: '/seguimiento')]),
    TypedStatefulShellBranch<RamaAvisos>(routes: [TypedGoRoute<RutaAvisos>(path: '/avisos')]),
  ],
)
class RutaPrincipal extends StatefulShellRouteData {
  const RutaPrincipal();

  @override
  Widget builder(BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) =>
      _Principal(shell: navigationShell);
}

class RamaBuscar extends StatefulShellBranchData {
  const RamaBuscar();
}

class RamaSeguimiento extends StatefulShellBranchData {
  const RamaSeguimiento();
}

class RamaAvisos extends StatefulShellBranchData {
  const RamaAvisos();
}

class RutaBuscar extends GoRouteData with $RutaBuscar {
  const RutaBuscar();

  @override
  Widget build(BuildContext context, GoRouterState state) => const PantallaBuscar();
}

class RutaSeguimiento extends GoRouteData with $RutaSeguimiento {
  const RutaSeguimiento();

  @override
  Widget build(BuildContext context, GoRouterState state) => const PantallaSeguimiento();
}

class RutaAvisos extends GoRouteData with $RutaAvisos {
  const RutaAvisos();

  @override
  Widget build(BuildContext context, GoRouterState state) => const PantallaAvisos();
}

/// La ficha se abre por encima de las secciones (también desde un aviso: `/licitaciones/123`).
@TypedGoRoute<RutaFicha>(
  path: '/licitaciones/:id',
  routes: [TypedGoRoute<RutaEditor>(path: 'seguimiento')],
)
class RutaFicha extends GoRouteData with $RutaFicha {
  const RutaFicha({required this.id});

  static final GlobalKey<NavigatorState> $parentNavigatorKey = claveRaiz;

  final int id;

  @override
  Widget build(BuildContext context, GoRouterState state) => PantallaFicha(id: id);
}

class RutaEditor extends GoRouteData with $RutaEditor {
  const RutaEditor({required this.id});

  static final GlobalKey<NavigatorState> $parentNavigatorKey = claveRaiz;

  final int id;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      MaterialPage(fullscreenDialog: true, child: PantallaEditor(id: id));
}

GoRouter crearRouter({String? inicial}) => GoRouter(
  navigatorKey: claveRaiz,
  routes: $appRoutes,
  initialLocation: inicial ?? '/',
  errorBuilder: (context, state) => const PantallaBuscar(),
);

class _Principal extends StatelessWidget {
  const _Principal({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
        NavigationDestination(
          icon: Icon(Icons.bookmarks_outlined),
          selectedIcon: Icon(Icons.bookmarks),
          label: 'Seguimiento',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_none),
          selectedIcon: Icon(Icons.notifications),
          label: 'Avisos',
        ),
      ],
    ),
  );
}
