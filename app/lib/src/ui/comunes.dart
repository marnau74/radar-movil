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

/// El color de lo que queda de plazo: ámbar si cierra en tres días o menos, verde si hay margen, gris si ya ha
/// cerrado o no hay plazo.
Color colorDePlazo(BuildContext context, Urgencia urgencia) {
  final c = context.estados;
  return switch (urgencia) {
    Urgencia.cerrado || Urgencia.sinPlazo => c.textoSuave,
    Urgencia.hoy || Urgencia.pronto => c.pendiente,
    Urgencia.holgado => c.enPlazo,
  };
}

Color colorDeEtapa(BuildContext context, Etapa etapa) => switch (etapa) {
  Etapa.ganada => context.estados.enPlazo,
  Etapa.perdida || Etapa.descartada => context.estados.textoSuave,
  _ => Theme.of(context).colorScheme.primary,
};

/// El día en que cierra el plazo, como la hoja de un calendario: lo primero que se mira de una licitación.
class SelloDePlazo extends ConsumerWidget {
  const SelloDePlazo(this.plazo, {this.anulada = false, super.key});

  final DateTime? plazo;
  final bool anulada;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final restante = plazoRestante(plazo, ref.watch(relojProvider)());
    final color = anulada ? context.estados.anulada : colorDePlazo(context, restante.urgencia);
    final local = plazo?.toLocal();
    return Semantics(
      label: anulada ? 'Anulada' : 'Plazo: ${restante.texto}',
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        child: Column(
          children: [
            Text(
              local == null ? '—' : '${local.day}',
              style: tema.textTheme.titleLarge?.merge(cifras).copyWith(color: color, height: 1.1),
            ),
            Text(
              local == null ? 'SIN PLAZO' : mesCorto(local),
              style: tema.textTheme.labelSmall?.copyWith(color: color, letterSpacing: 0.6, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que queda de plazo, en texto y con su color («Cierra mañana a las 14:00»).
class TextoDePlazo extends ConsumerWidget {
  const TextoDePlazo(this.plazo, {super.key});

  final DateTime? plazo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restante = plazoRestante(plazo, ref.watch(relojProvider)());
    return Text(
      restante.texto,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colorDePlazo(context, restante.urgencia)),
    );
  }
}

/// La etapa de un seguimiento: un punto de color y su nombre.
class TextoDeEtapa extends StatelessWidget {
  const TextoDeEtapa(this.etapa, {super.key});

  final Etapa etapa;

  @override
  Widget build(BuildContext context) {
    final color = colorDeEtapa(context, etapa);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 7),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            etapa.corto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Una licitación en una lista: el sello del plazo a la izquierda y, a la derecha, órgano, título, importe y lugar.
/// Sin caja alrededor: las filas se separan con una línea fina.
class FilaDeLicitacion extends ConsumerWidget {
  const FilaDeLicitacion({
    required this.titulo,
    required this.organo,
    required this.alTocar,
    this.importe,
    this.plazo,
    this.lugar,
    this.anulada = false,
    this.etapa,
    this.indicador,
    super.key,
  });

  factory FilaDeLicitacion.deResumen(LicitacionResumen l, {required VoidCallback alTocar, Etapa? etapa, Key? key}) =>
      FilaDeLicitacion(
        key: key,
        titulo: l.titulo,
        organo: l.organo,
        importe: l.importeSinIva,
        plazo: l.plazoPresentacion,
        lugar: l.lugar,
        anulada: l.anulada,
        etapa: etapa,
        alTocar: alTocar,
      );

  final String titulo;
  final String organo;
  final double? importe;
  final DateTime? plazo;
  final String? lugar;
  final bool anulada;
  final Etapa? etapa;

  /// Un icono pequeño junto al título (pendiente de subir, conflicto).
  final Widget? indicador;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final suave = tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave);
    final restante = plazoRestante(plazo, ref.watch(relojProvider)());
    final urgente = restante.urgencia == Urgencia.hoy || restante.urgencia == Urgencia.pronto;
    final String detalle;
    final TextStyle? estiloDelDetalle;
    if (anulada) {
      detalle = 'Anulada';
      estiloDelDetalle = suave?.copyWith(color: context.estados.anulada, fontWeight: FontWeight.w600);
    } else if (urgente) {
      detalle = restante.texto;
      estiloDelDetalle = suave?.copyWith(color: context.estados.pendiente, fontWeight: FontWeight.w600);
    } else {
      detalle = lugar ?? '';
      estiloDelDetalle = suave;
    }
    return InkWell(
      onTap: alTocar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelloDePlazo(plazo, anulada: anulada),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(organo, maxLines: 1, overflow: TextOverflow.ellipsis, style: suave),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall?.copyWith(
                            decoration: anulada ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (indicador != null) ...[const SizedBox(width: 8), indicador!],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Semantics(
                        label: 'Importe sin IVA: ${euros(importe)}',
                        excludeSemantics: true,
                        child: Text(
                          euros(importe),
                          style: tema.textTheme.bodyMedium?.merge(cifras).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloDelDetalle),
                      ),
                      if (etapa != null) Flexible(child: TextoDeEtapa(etapa!)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un encabezado de sección, pequeño y en mayúsculas, como los de los ajustes del sistema.
class Encabezado extends StatelessWidget {
  const Encabezado(this.texto, {this.detalle, super.key});

  final String texto;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall?.copyWith(color: context.estados.textoSuave);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
        child: Row(
          children: [
            Expanded(child: Text(texto.toUpperCase(), style: estilo)),
            if (detalle != null) Text(detalle!, style: estilo?.merge(cifras)),
          ],
        ),
      ),
    );
  }
}
