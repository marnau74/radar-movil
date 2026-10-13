import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/ui/tema.dart';

class AppRadar extends ConsumerStatefulWidget {
  const AppRadar({required this.router, super.key});

  final GoRouter router;

  @override
  ConsumerState<AppRadar> createState() => _AppRadarState();
}

class _AppRadarState extends ConsumerState<AppRadar> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver a la app se sube lo pendiente y se trae lo cambiado en otros dispositivos.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(usuarioProvider).value != null) {
      unawaited(ref.read(sincronizacionProvider.notifier).sincronizar());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Radar móvil',
    debugShowCheckedModeBanner: false,
    theme: temaClaro(),
    darkTheme: temaOscuro(),
    routerConfig: widget.router,
    locale: const Locale('es', 'ES'),
    supportedLocales: const [Locale('es', 'ES')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
  );
}
