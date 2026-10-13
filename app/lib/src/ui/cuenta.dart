import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/ui/comunes.dart';

/// El botón de la cuenta en la barra superior: entrar, o ver con qué cuenta se está y salir.
class BotonDeCuenta extends ConsumerWidget {
  const BotonDeCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioProvider).value;
    if (usuario == null) {
      return TextButton(onPressed: () => iniciarSesion(context, ref), child: const Text('Entrar'));
    }
    return MenuAnchor(
      builder: (context, controlador, _) => IconButton(
        tooltip: 'Tu cuenta',
        icon: CircleAvatar(
          radius: 15,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            usuario.visible.characters.first.toUpperCase(),
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
          ),
        ),
        onPressed: () => controlador.isOpen ? controlador.close() : controlador.open(),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(usuario.visible, style: Theme.of(context).textTheme.titleSmall),
              if (usuario.correo != null && usuario.correo != usuario.visible)
                Text(usuario.correo!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => _cerrarSesion(context, ref),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    final pendientes = ref.read(estadoLocalProvider).pendientes;
    if (pendientes > 0) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay cambios sin subir'),
          content: Text(
            pendientes == 1
                ? 'Un cambio de tu seguimiento aún no ha llegado al servidor. Si cierras sesión ahora, se perderá.'
                : '$pendientes cambios de tu seguimiento aún no han llegado al servidor. Si cierras sesión ahora, '
                      'se perderán.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
          ],
        ),
      );
      if (seguir != true) return;
    }
    await ref.read(serviciosProvider).cerrarSesion();
  }
}
