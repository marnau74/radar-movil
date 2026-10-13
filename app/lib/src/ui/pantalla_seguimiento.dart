import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/modelos/embudo.dart';
import 'package:radar_movil/src/modelos/seguimiento.dart';
import 'package:radar_movil/src/red/errores.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/cuenta.dart';
import 'package:radar_movil/src/ui/formato.dart';
import 'package:radar_movil/src/ui/tema.dart';

/// El embudo de ofertas: cifras por etapa arriba y los seguimientos agrupados por etapa debajo. Funciona sin red.
class PantallaSeguimiento extends ConsumerStatefulWidget {
  const PantallaSeguimiento({super.key});

  @override
  ConsumerState<PantallaSeguimiento> createState() => _PantallaSeguimientoState();
}

class _PantallaSeguimientoState extends ConsumerState<PantallaSeguimiento> {
  Etapa? _filtro;

  Future<void> _sincronizar() async {
    final mensajero = ScaffoldMessenger.of(context);
    final resultado = await ref.read(sincronizacionProvider.notifier).sincronizar();
    final error = resultado.error;
    if (error != null) mensajero.showSnackBar(SnackBar(content: Text(error.mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(usuarioProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Seguimiento'), actions: const [BotonDeCuenta()]),
      body: usuario == null
          ? const InvitacionAEntrar(
              texto: 'Tu seguimiento se guarda en tu cuenta y se comparte entre tus dispositivos.',
            )
          : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    final lista = ref.watch(seguimientosProvider);
    return switch (lista) {
      AsyncValue(:final value?) when value.isEmpty => RefreshIndicator(
        onRefresh: _sincronizar,
        child: LayoutBuilder(
          builder: (context, medidas) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: medidas.maxHeight,
              child: const Vacio(
                icono: Icons.bookmarks_outlined,
                titulo: 'Aún no sigues ninguna licitación',
                texto: 'Abre una licitación desde la búsqueda y pulsa «Seguir» para llevarla por tu embudo.',
              ),
            ),
          ),
        ),
      ),
      AsyncValue(:final value?) => RefreshIndicator(onRefresh: _sincronizar, child: _lista(value)),
      AsyncValue(:final error?) => ErrorConReintento(
        error: error,
        reintentar: () => ref.invalidate(seguimientosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _lista(List<SeguimientoLocal> todos) {
    final embudo = ref.watch(embudoProvider);
    final visibles = _filtro == null ? todos : todos.where((s) => s.seguimiento.etapa == _filtro).toList();
    final etapas = Etapa.values.where((e) => visibles.any((s) => s.seguimiento.etapa == e));
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: _AvisoDeSincronizacion()),
        SliverToBoxAdapter(child: _Resumen(embudo: embudo)),
        SliverToBoxAdapter(
          child: _FiltroDeEtapas(
            embudo: embudo,
            elegida: _filtro,
            alElegir: (etapa) => setState(() => _filtro = etapa == _filtro ? null : etapa),
          ),
        ),
        for (final etapa in etapas) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Semantics(
                header: true,
                child: Text(
                  etapa.nombre,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.estados.textoSuave),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: visibles.where((s) => s.seguimiento.etapa == etapa).length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _Fila(local: visibles.where((s) => s.seguimiento.etapa == etapa).elementAt(i)),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// Cambios sin subir o conflictos: se explica qué pasa en vez de esconderlo.
class _AvisoDeSincronizacion extends ConsumerWidget {
  const _AvisoDeSincronizacion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoLocalProvider);
    final ultimo = ref.watch(sincronizacionProvider);
    final c = context.estados;
    final String texto;
    if (estado.conflictos > 0) {
      texto = estado.conflictos == 1
          ? 'Un seguimiento se ha cambiado también en otro dispositivo. Ábrelo para elegir qué versión se queda.'
          : '${estado.conflictos} seguimientos se han cambiado también en otro dispositivo. Ábrelos para elegir.';
    } else if (estado.pendientes > 0) {
      final motivo = ultimo?.error is SinConexion ? ' Sin conexión: se subirán al volver la red.' : '';
      texto = estado.pendientes == 1
          ? 'Un cambio guardado en el móvil, pendiente de subir.$motivo'
          : '${estado.pendientes} cambios guardados en el móvil, pendientes de subir.$motivo';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.pendienteFondo, borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(estado.conflictos > 0 ? Icons.sync_problem : Icons.cloud_upload_outlined, color: c.pendiente),
              const SizedBox(width: 10),
              Expanded(child: Text(texto)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.embudo});

  final Embudo embudo;

  @override
  Widget build(BuildContext context) {
    final tasa = embudo.tasaDeExito;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      // Las dos cifras, igual de altas aunque una tenga más texto.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Cifra(
                nombre: 'En juego',
                valor: euros(embudo.importeEnJuego),
                detalle: '${embudo.abiertas} abiertas',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Cifra(
                nombre: 'Tasa de éxito',
                valor: tasa == null ? '—' : porcentaje(tasa),
                detalle:
                    '${embudo.cifras(Etapa.ganada).cuantas} ganadas de '
                    '${embudo.cifras(Etapa.ganada).cuantas + embudo.cifras(Etapa.perdida).cuantas} resueltas',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.nombre, required this.valor, required this.detalle});

  final String nombre;
  final String valor;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          label: '$nombre: $valor, $detalle',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: tema.textTheme.labelMedium?.copyWith(color: context.estados.textoSuave)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  valor,
                  style: tema.textTheme.titleLarge?.merge(cifras).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 2),
              Text(detalle, style: tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una ficha por etapa con su contador; tocarla filtra la lista.
class _FiltroDeEtapas extends StatelessWidget {
  const _FiltroDeEtapas({required this.embudo, required this.elegida, required this.alElegir});

  final Embudo embudo;
  final Etapa? elegida;
  final ValueChanged<Etapa> alElegir;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      itemCount: Etapa.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final etapa = Etapa.values[i];
        final cuantas = embudo.cifras(etapa).cuantas;
        return FilterChip(
          label: Text('${etapa.nombre} · $cuantas'),
          selected: etapa == elegida,
          onSelected: cuantas == 0 && etapa != elegida ? null : (_) => alElegir(etapa),
        );
      },
    ),
  );
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.local});

  final SeguimientoLocal local;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = local.seguimiento;
    final tema = Theme.of(context);
    final suave = tema.textTheme.bodySmall?.copyWith(color: context.estados.textoSuave);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => RutaFicha(id: s.licitacionId).push<void>(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      s.resumen.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  if (local.enConflicto)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.sync_problem,
                        size: 20,
                        color: context.estados.pendiente,
                        semanticLabel: 'En conflicto',
                      ),
                    )
                  else if (local.pendiente)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 20,
                        color: context.estados.textoSuave,
                        semanticLabel: 'Pendiente de subir',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.resumen.organo, maxLines: 1, overflow: TextOverflow.ellipsis, style: suave),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    euros(s.resumen.importe),
                    style: tema.textTheme.bodyMedium?.merge(cifras).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (!s.etapa.cerrada) EtiquetaDePlazo(s.resumen.plazo),
                  if (s.responsable != null) Text(s.responsable!, style: suave),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
