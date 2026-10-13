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
          child: _Pestanas(
            embudo: embudo,
            total: todos.length,
            elegida: _filtro,
            alElegir: (etapa) => setState(() => _filtro = etapa),
          ),
        ),
        const SliverToBoxAdapter(child: Divider()),
        for (final etapa in etapas) ...[
          SliverToBoxAdapter(
            child: Encabezado(
              etapa.nombre,
              detalle: euros(
                visibles
                    .where((s) => s.seguimiento.etapa == etapa)
                    .fold<double>(0, (suma, s) => suma + (s.seguimiento.resumen.importe ?? 0)),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: visibles.where((s) => s.seguimiento.etapa == etapa).length,
            separatorBuilder: (_, _) => const Divider(indent: 74),
            itemBuilder: (context, i) => _Fila(local: visibles.where((s) => s.seguimiento.etapa == etapa).elementAt(i)),
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
    final tema = Theme.of(context);
    final suave = tema.textTheme.bodyMedium?.copyWith(color: context.estados.textoSuave);
    final ganadas = embudo.cifras(Etapa.ganada).cuantas;
    final resueltas = ganadas + embudo.cifras(Etapa.perdida).cuantas;
    final tasa = embudo.tasaDeExito;
    final abiertas = embudo.abiertas == 1 ? '1 oferta abierta' : '${embudo.abiertas} ofertas abiertas';
    final exito = tasa == null ? 'aún ninguna resuelta' : '$ganadas de $resueltas ganadas (${porcentaje(tasa)})';
    return Semantics(
      label: 'En juego: ${euros(embudo.importeEnJuego)} en $abiertas; $exito',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EN JUEGO', style: tema.textTheme.labelSmall?.copyWith(color: context.estados.textoSuave)),
            const SizedBox(height: 2),
            Text(
              euros(embudo.importeEnJuego),
              style: tema.textTheme.displaySmall
                  ?.merge(cifras)
                  .copyWith(fontWeight: FontWeight.w600, letterSpacing: -1, color: tema.colorScheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text('en $abiertas · $exito', style: suave),
            const SizedBox(height: 16),
            _Barra(embudo: embudo),
          ],
        ),
      ),
    );
  }
}

/// Cuántas hay en cada etapa, como una barra repartida: se ve de un vistazo dónde se acumulan las ofertas.
class _Barra extends StatelessWidget {
  const _Barra({required this.embudo});

  final Embudo embudo;

  @override
  Widget build(BuildContext context) {
    final primario = Theme.of(context).colorScheme.primary;
    final colores = {
      Etapa.interesa: primario.withValues(alpha: 0.3),
      Etapa.preparando: primario.withValues(alpha: 0.6),
      Etapa.presentada: primario,
      Etapa.ganada: context.estados.enPlazo,
      Etapa.perdida: context.estados.textoSuave.withValues(alpha: 0.5),
      Etapa.descartada: context.estados.textoSuave.withValues(alpha: 0.25),
    };
    final etapas = Etapa.values.where((e) => embudo.cifras(e).cuantas > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, etapa) in etapas.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: embudo.cifras(etapa).cuantas,
                child: ColoredBox(color: colores[etapa]!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pestañas de texto con el número de cada etapa; solo las que tienen algo.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.embudo, required this.total, required this.elegida, required this.alElegir});

  final Embudo embudo;
  final int total;
  final Etapa? elegida;
  final ValueChanged<Etapa?> alElegir;

  @override
  Widget build(BuildContext context) {
    final etapas = Etapa.values.where((e) => embudo.cifras(e).cuantas > 0);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        children: [
          _Pestana(texto: 'Todas $total', elegida: elegida == null, alTocar: () => alElegir(null)),
          for (final e in etapas)
            _Pestana(
              texto: '${e.corto} ${embudo.cifras(e).cuantas}',
              elegida: elegida == e,
              alTocar: () => alElegir(e),
            ),
        ],
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({required this.texto, required this.elegida, required this.alTocar});

  final String texto;
  final bool elegida;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      selected: elegida,
      button: true,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: elegida ? tema.colorScheme.onSurface : Colors.transparent, width: 2),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            texto,
            style: tema.textTheme.labelLarge
                ?.merge(cifras)
                .copyWith(
                  color: elegida ? tema.colorScheme.onSurface : context.estados.textoSuave,
                  fontWeight: elegida ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.local});

  final SeguimientoLocal local;

  @override
  Widget build(BuildContext context) {
    final s = local.seguimiento;
    final Widget? indicador;
    if (local.enConflicto) {
      indicador = Icon(Icons.sync_problem, size: 18, color: context.estados.pendiente, semanticLabel: 'En conflicto');
    } else if (local.pendiente) {
      indicador = Icon(
        Icons.cloud_upload_outlined,
        size: 18,
        color: context.estados.textoSuave,
        semanticLabel: 'Pendiente de subir',
      );
    } else {
      indicador = null;
    }
    return FilaDeLicitacion(
      titulo: s.resumen.titulo,
      organo: s.resumen.organo,
      importe: s.resumen.importe,
      // En las cerradas el plazo ya no importa: se enseña en gris como «sin plazo».
      plazo: s.etapa.cerrada ? null : s.resumen.plazo,
      lugar: s.responsable,
      indicador: indicador,
      alTocar: () => RutaFicha(id: s.licitacionId).push<void>(context),
    );
  }
}
