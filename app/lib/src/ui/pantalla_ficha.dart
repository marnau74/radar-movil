import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/licitacion.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/formato.dart';
import 'package:radar_movil/src/ui/seguimiento_de_la_ficha.dart';
import 'package:radar_movil/src/ui/tema.dart';
import 'package:url_launcher/url_launcher.dart';

/// La ficha de una licitación, con su seguimiento debajo del título.
class PantallaFicha extends ConsumerWidget {
  const PantallaFicha({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ficha = ref.watch(fichaProvider(id));
    // Si se sigue, el resumen guardado se pone al día con la ficha recién leída (el plazo puede haber cambiado).
    ref.listen(fichaProvider(id), (_, siguiente) => _actualizarResumen(ref, siguiente.value));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Licitación'),
        actions: [
          if (ficha.value?.url != null)
            IconButton(
              tooltip: 'Abrir en la Plataforma de Contratación',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _abrir(context, ficha.value!.url!),
            ),
        ],
      ),
      body: switch (ficha) {
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => ref.refresh(fichaProvider(id).future),
          child: _Contenido(ficha: value),
        ),
        AsyncValue(:final error?) => ErrorConReintento(
          error: error,
          reintentar: () => ref.invalidate(fichaProvider(id)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _actualizarResumen(WidgetRef ref, FichaDeLicitacion? ficha) {
    final local = ref.read(seguimientoDeProvider(id)).value;
    if (ficha == null || local == null) return;
    unawaited(ref.read(sincronizacionProvider.notifier).actualizarResumen(local, ficha));
  }
}

Future<void> _abrir(BuildContext context, String url) async {
  final mensajero = ScaffoldMessenger.of(context);
  final abierto = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!abierto) mensajero.showSnackBar(const SnackBar(content: Text('No se ha podido abrir el enlace')));
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.ficha});

  final FichaDeLicitacion ficha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final f = ficha;
    final suave = tema.textTheme.bodyMedium?.copyWith(color: context.estados.textoSuave);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            EtiquetaDePlazo(f.plazoPresentacion, anulada: f.anulada),
            Etiqueta(f.estado.nombre, color: context.estados.cerrada, fondo: context.estados.cerradaFondo),
            if (f.financiacionUe)
              Etiqueta('Fondos UE', color: tema.colorScheme.primary, fondo: tema.colorScheme.primaryContainer),
          ],
        ),
        const SizedBox(height: 12),
        Text(f.titulo, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
        const SizedBox(height: 6),
        Text(f.organo.nombre, style: suave),
        if (f.expediente != null) Text('Expediente ${f.expediente}', style: suave),
        const SizedBox(height: 16),
        SeguimientoDeLaFicha(ficha: f),
        const SizedBox(height: 16),
        _Seccion(
          titulo: 'Datos',
          hijos: [
            _Dato('Importe sin IVA', euros(f.importeSinIva), cifra: true),
            if (f.importeConIva != null) _Dato('Importe con IVA', euros(f.importeConIva), cifra: true),
            if (f.valorEstimado != null) _Dato('Valor estimado', euros(f.valorEstimado), cifra: true),
            _Dato('Fin del plazo', fechaHora(f.plazoPresentacion)),
            _Dato('Publicada', fecha(f.fechaPublicacion)),
            if (f.tipoContrato != null) _Dato('Tipo de contrato', f.tipoContrato!.nombre),
            if (f.procedimiento != null) _Dato('Procedimiento', f.procedimiento!.nombre),
            if (f.duracion != null) _Dato('Duración', f.duracion!),
            if (f.lugar != null) _Dato('Lugar', f.lugar!),
          ],
        ),
        if (f.cpv.isNotEmpty)
          _Seccion(titulo: 'Clasificación CPV', hijos: [for (final c in f.cpv) _Dato(c.codigo, c.nombre)]),
        if (f.lotes.isNotEmpty)
          _Seccion(
            titulo: f.lotes.length == 1 ? '1 lote' : '${f.lotes.length} lotes',
            hijos: [
              for (final l in f.lotes)
                _Dato('Lote ${l.numero}', l.objeto ?? 'Sin descripción', derecha: euros(l.importeSinIva)),
            ],
          ),
        if (f.resultados.isNotEmpty)
          _Seccion(
            titulo: 'Adjudicación',
            hijos: [
              for (final r in f.resultados)
                _Dato(
                  [if (r.lote != null) 'Lote ${r.lote}', r.resultado?.nombre ?? 'Resultado'].join(' · '),
                  [
                    r.adjudicatario ?? 'Sin adjudicatario',
                    if (r.ofertasRecibidas != null) '${r.ofertasRecibidas} ofertas',
                  ].join(' · '),
                  derecha: r.importeSinIva == null ? null : euros(r.importeSinIva),
                ),
            ],
          ),
        if (f.documentos.isNotEmpty)
          _Seccion(
            titulo: 'Pliegos y documentos',
            hijos: [
              for (final d in f.documentos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(d.descripcion),
                  subtitle: d.nombre == null || d.nombre == d.descripcion
                      ? null
                      : Text(d.nombre!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _abrir(context, d.url),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Datos de la Plataforma de Contratación del Sector Público, a través del radar.',
          style: tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijos});

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            ...hijos,
          ],
        ),
      ),
    ),
  );
}

class _Dato extends StatelessWidget {
  const _Dato(this.nombre, this.valor, {this.cifra = false, this.derecha});

  final String nombre;
  final String valor;
  final bool cifra;
  final String? derecha;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: tema.textTheme.labelMedium?.copyWith(color: context.estados.textoSuave)),
                const SizedBox(height: 2),
                Text(valor, style: cifra ? tema.textTheme.bodyLarge?.merge(cifras) : tema.textTheme.bodyMedium),
              ],
            ),
          ),
          if (derecha != null) ...[
            const SizedBox(width: 12),
            Text(derecha!, style: tema.textTheme.bodyMedium?.merge(cifras)),
          ],
        ],
      ),
    );
  }
}
