import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/cuenta.dart';
import 'package:radar_movil/src/ui/formato.dart';
import 'package:radar_movil/src/ui/tema.dart';

/// Lo que han encontrado las alertas que el usuario tiene en el radar (las alertas se configuran en la web).
class PantallaAvisos extends ConsumerWidget {
  const PantallaAvisos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioProvider).value;
    final avisos = ref.watch(avisosDelRadarProvider);
    final hayNoLeidos = avisos.value?.elementos.any((a) => !a.leido) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [
          if (hayNoLeidos)
            IconButton(
              tooltip: 'Marcar todos como leídos',
              icon: const Icon(Icons.done_all),
              onPressed: () => _marcarLeidos(context, ref),
            ),
          const BotonDeCuenta(),
        ],
      ),
      body: usuario == null
          ? const InvitacionAEntrar(texto: 'Aquí verás lo que encuentran las alertas que tienes en el radar.')
          : switch (avisos) {
              AsyncValue(:final value?) when value.elementos.isEmpty => const Vacio(
                icono: Icons.notifications_none,
                titulo: 'Sin avisos',
                texto:
                    'Cuando tus alertas del radar encuentren licitaciones nuevas, aparecerán aquí. Las alertas se '
                    'crean en la web del radar.',
              ),
              AsyncValue(:final value?) => RefreshIndicator(
                onRefresh: () => ref.refresh(avisosDelRadarProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: value.elementos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final aviso = value.elementos[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 2),
                          child: Row(
                            children: [
                              if (!aviso.leido) ...[
                                Icon(Icons.circle, size: 8, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  '${aviso.alerta} · ${fecha(aviso.creadoEn)}',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: context.estados.textoSuave),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TarjetaDeLicitacion(
                          licitacion: aviso.licitacion,
                          alTocar: () => RutaFicha(id: aviso.licitacion.id).push<void>(context),
                        ),
                      ],
                    );
                  },
                ),
              ),
              AsyncValue(:final error?) => ErrorConReintento(
                error: error,
                reintentar: () => ref.invalidate(avisosDelRadarProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }

  Future<void> _marcarLeidos(BuildContext context, WidgetRef ref) async {
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await ref.read(serviciosProvider).radar.marcarAvisosLeidos();
      ref.invalidate(avisosDelRadarProvider);
    } on Object catch (error) {
      mensajero.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
    }
  }
}
