import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/sesion/sesion.dart';
import 'package:radar_movil/src/ui/formato.dart';
import 'package:radar_movil/src/ui/tema.dart';

/// El texto que se enseña de un error: el de la API si es conocido, uno genérico si no.
String mensajeDeError(Object error) => error is ErrorDeApi ? error.mensaje : 'Algo ha fallado. Inténtalo de nuevo.';

/// Una pantalla o sección vacía, con su explicación y, si la hay, la acción que lo arregla.
class Vacio extends StatelessWidget {
  const Vacio({required this.icono, required this.titulo, this.texto, this.accion, super.key});

  final IconData icono;
  final String titulo;
  final String? texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 40, color: context.estados.textoSuave),
            const SizedBox(height: 16),
            Text(titulo, style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
            if (texto != null) ...[
              const SizedBox(height: 8),
              Text(
                texto!,
                style: tema.textTheme.bodyMedium?.copyWith(color: context.estados.textoSuave),
                textAlign: TextAlign.center,
              ),
            ],
            if (accion != null) ...[const SizedBox(height: 20), accion!],
          ],
        ),
      ),
    );
  }
}

class ErrorConReintento extends StatelessWidget {
  const ErrorConReintento({required this.error, required this.reintentar, super.key});

  final Object error;
  final VoidCallback reintentar;

  @override
  Widget build(BuildContext context) => Vacio(
    icono: error is SinConexion ? Icons.cloud_off_outlined : Icons.error_outline,
    titulo: error is SinConexion ? 'Sin conexión' : 'No se ha podido cargar',
    texto: mensajeDeError(error),
    accion: OutlinedButton.icon(
      onPressed: reintentar,
      icon: const Icon(Icons.refresh),
      label: const Text('Reintentar'),
    ),
  );
}

/// Para las secciones que necesitan cuenta.
class InvitacionAEntrar extends ConsumerWidget {
  const InvitacionAEntrar({required this.texto, super.key});

  final String texto;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Vacio(
    icono: Icons.lock_outline,
    titulo: 'Inicia sesión',
    texto: texto,
    accion: FilledButton(
      onPressed: () => iniciarSesion(context, ref),
      child: const Text('Iniciar sesión con tu cuenta del radar'),
    ),
  );
}

/// Abre el inicio de sesión de Keycloak en el navegador del sistema. Cancelarlo no es un error.
Future<void> iniciarSesion(BuildContext context, WidgetRef ref) async {
  final mensajero = ScaffoldMessenger.of(context);
  try {
    await ref.read(serviciosProvider).sesion.iniciar();
    await ref.read(sincronizacionProvider.notifier).sincronizar();
  } on InicioCancelado {
    return;
  } on Object catch (error) {
    debugPrint('Inicio de sesión fallido: $error');
    mensajero.showSnackBar(const SnackBar(content: Text('No se ha podido iniciar sesión. Comprueba la conexión.')));
  }
}

/// Una etiqueta pequeña de color apagado, como las de la web del radar.
class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {required this.color, required this.fondo, this.icono, super.key});

  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class EtiquetaDePlazo extends ConsumerWidget {
  const EtiquetaDePlazo(this.plazo, {this.anulada = false, super.key});

  final DateTime? plazo;
  final bool anulada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.estados;
    if (anulada) return Etiqueta('Anulada', color: c.anulada, fondo: c.anuladaFondo);
    final restante = plazoRestante(plazo, ref.watch(relojProvider)());
    final (color, fondo) = switch (restante.urgencia) {
      Urgencia.cerrado || Urgencia.sinPlazo => (c.cerrada, c.cerradaFondo),
      Urgencia.hoy || Urgencia.pronto => (c.pendiente, c.pendienteFondo),
      Urgencia.holgado => (c.enPlazo, c.enPlazoFondo),
    };
    return Semantics(
      label: 'Plazo: ${restante.texto}',
      excludeSemantics: true,
      child: Etiqueta(restante.texto, color: color, fondo: fondo, icono: Icons.schedule),
    );
  }
}

class EtiquetaDeEtapa extends StatelessWidget {
  const EtiquetaDeEtapa(this.etapa, {super.key});

  final Etapa etapa;

  @override
  Widget build(BuildContext context) {
    final c = context.estados;
    final colores = Theme.of(context).colorScheme;
    final (color, fondo) = switch (etapa) {
      Etapa.ganada => (c.enPlazo, c.enPlazoFondo),
      Etapa.perdida || Etapa.descartada => (c.cerrada, c.cerradaFondo),
      _ => (colores.primary, colores.primaryContainer),
    };
    return Etiqueta(etapa.nombre, color: color, fondo: fondo, icono: Icons.flag_outlined);
  }
}

/// Una licitación en una lista. Si se sigue, enseña en qué etapa está.
class TarjetaDeLicitacion extends StatelessWidget {
  const TarjetaDeLicitacion({required this.licitacion, required this.alTocar, this.etapa, super.key});

  final LicitacionResumen licitacion;
  final Etapa? etapa;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final l = licitacion;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.titulo,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 6),
              Text(
                l.organo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Semantics(
                    label: 'Importe sin IVA: ${euros(l.importeSinIva)}',
                    excludeSemantics: true,
                    child: Text(
                      euros(l.importeSinIva),
                      style: tema.textTheme.titleSmall?.merge(cifras).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (l.lugar != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l.lugar!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave),
                      ),
                    ),
                  ] else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  EtiquetaDePlazo(l.plazoPresentacion, anulada: l.anulada),
                  if (etapa != null) EtiquetaDeEtapa(etapa!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
