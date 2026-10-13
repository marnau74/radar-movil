import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/formato.dart';
import 'package:radar_movil/src/ui/tema.dart';

/// El bloque del seguimiento en la ficha: seguir, cambiar de etapa, editar o resolver un conflicto.
class SeguimientoDeLaFicha extends ConsumerWidget {
  const SeguimientoDeLaFicha({required this.ficha, super.key});

  final FichaDeLicitacion ficha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioProvider).value;
    if (usuario == null) {
      return _Marco(
        child: Row(
          children: [
            const Expanded(child: Text('Inicia sesión para seguir esta licitación y llevarla en tu embudo.')),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: () => iniciarSesion(context, ref), child: const Text('Entrar')),
          ],
        ),
      );
    }
    final local = ref.watch(seguimientoDeProvider(ficha.id));
    return switch (local) {
      AsyncValue(value: final SeguimientoLocal s) when s.enConflicto => _Conflicto(local: s),
      AsyncValue(value: final SeguimientoLocal s) => _Seguido(local: s),
      AsyncValue(hasValue: true) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _ejecutar(context, () => ref.read(sincronizacionProvider.notifier).seguir(ficha)),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Seguir esta licitación'),
        ),
      ),
      _ => const SizedBox(height: 48),
    };
  }
}

/// Ejecuta una acción del seguimiento enseñando el error, si lo hay. Los errores de red no se enseñan: el cambio ya
/// está guardado en el móvil y se subirá después.
Future<void> _ejecutar(BuildContext context, Future<void> Function() accion) async {
  final mensajero = ScaffoldMessenger.of(context);
  try {
    await accion();
  } on Object catch (error) {
    mensajero.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
  }
}

class _Marco extends StatelessWidget {
  const _Marco({required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colores.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colores.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _Seguido extends ConsumerWidget {
  const _Seguido({required this.local});

  final SeguimientoLocal local;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = local.seguimiento;
    final tema = Theme.of(context);
    final suave = tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave);
    return _Marco(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tu seguimiento', style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (local.pendiente)
                Tooltip(
                  message: 'Guardado en el móvil, pendiente de subir',
                  child: Icon(Icons.cloud_upload_outlined, size: 20, color: context.estados.pendiente),
                ),
              _MenuDelSeguimiento(local: local),
            ],
          ),
          const SizedBox(height: 4),
          _SelectorDeEtapa(seguimiento: s),
          if (s.responsable != null || s.fechaInterna != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (s.responsable != null) Text('Responsable: ${s.responsable}', style: suave),
                if (s.fechaInterna != null) Text('Fecha interna: ${fecha(s.fechaInterna)}', style: suave),
              ],
            ),
          ],
          if (s.notas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.notas, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => RutaEditor(id: s.licitacionId).push<void>(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Notas, responsable y fecha'),
            ),
          ),
        ],
      ),
    );
  }
}

/// El cambio de etapa es un menú, no un tablero que se arrastra: en el móvil se usa mejor y es accesible.
class _SelectorDeEtapa extends ConsumerWidget {
  const _SelectorDeEtapa({required this.seguimiento});

  final Seguimiento seguimiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DropdownMenu<Etapa>(
    initialSelection: seguimiento.etapa,
    label: const Text('Etapa'),
    expandedInsets: EdgeInsets.zero,
    requestFocusOnTap: false,
    dropdownMenuEntries: [for (final e in Etapa.values) DropdownMenuEntry(value: e, label: e.nombre)],
    onSelected: (etapa) {
      if (etapa == null || etapa == seguimiento.etapa) return;
      final ahora = ref.read(relojProvider)();
      unawaited(
        _ejecutar(context, () => ref.read(sincronizacionProvider.notifier).guardar(seguimiento.conEtapa(etapa, ahora))),
      );
    },
  );
}

class _MenuDelSeguimiento extends ConsumerWidget {
  const _MenuDelSeguimiento({required this.local});

  final SeguimientoLocal local;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MenuAnchor(
    builder: (context, controlador, _) => IconButton(
      tooltip: 'Más opciones',
      icon: const Icon(Icons.more_vert),
      onPressed: () => controlador.isOpen ? controlador.close() : controlador.open(),
    ),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.bookmark_remove_outlined),
        onPressed: () => _dejarDeSeguir(context, ref),
        child: const Text('Dejar de seguir'),
      ),
    ],
  );

  Future<void> _dejarDeSeguir(BuildContext context, WidgetRef ref) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Dejar de seguir?'),
        content: const Text('Se borrarán la etapa, las notas y el historial de esta licitación.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Dejar de seguir')),
        ],
      ),
    );
    if (seguro != true || !context.mounted) return;
    await _ejecutar(context, () => ref.read(sincronizacionProvider.notifier).dejarDeSeguir(local.licitacionId));
  }
}

/// Las dos versiones, una al lado de la otra, para elegir. Nunca se pisa un cambio en silencio.
class _Conflicto extends ConsumerWidget {
  const _Conflicto({required this.local});

  final SeguimientoLocal local;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final mio = local.seguimiento;
    final otro = local.delServidor;
    final acciones = ref.read(sincronizacionProvider.notifier);
    return _Marco(
      color: context.estados.pendienteFondo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync_problem, color: context.estados.pendiente),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cambiado en otro dispositivo',
                  style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            otro == null ? 'Mientras hacías estos cambios, se dejó de seguir desde otro dispositivo.' : 'Mientras hacías estos cambios, se guardaron otros desde otro dispositivo. Elige con cuáles te quedas.',
          ),
          const SizedBox(height: 12),
          _Version(titulo: 'En este móvil', s: mio),
          if (otro != null) ...[const SizedBox(height: 8), _Version(titulo: 'Guardado', s: otro)],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _ejecutar(context, () => acciones.quedarmeConLoMio(mio.licitacionId)),
                child: const Text('Quedarme con lo de este móvil'),
              ),
              OutlinedButton(
                onPressed: () => _ejecutar(context, () => acciones.usarLoDelServidor(mio.licitacionId)),
                child: Text(otro == null ? 'Dejar de seguirla' : 'Usar lo guardado'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Version extends StatelessWidget {
  const _Version({required this.titulo, required this.s});

  final String titulo;
  final Seguimiento s;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: tema.textTheme.labelLarge?.copyWith(color: context.estados.textoSuave)),
            const SizedBox(height: 6),
            EtiquetaDeEtapa(s.etapa),
            if (s.responsable != null) ...[const SizedBox(height: 4), Text('Responsable: ${s.responsable}')],
            if (s.notas.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(s.notas, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
