import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/red/apis.dart';
import 'package:radar_movil/src/rutas.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/cuenta.dart';
import 'package:radar_movil/src/ui/tema.dart';

/// Buscar licitaciones en el radar. Es pública: no hace falta cuenta.
class PantallaBuscar extends ConsumerStatefulWidget {
  const PantallaBuscar({super.key});

  @override
  ConsumerState<PantallaBuscar> createState() => _PantallaBuscarState();
}

class _PantallaBuscarState extends ConsumerState<PantallaBuscar> {
  final _texto = TextEditingController();
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _texto.text = ref.read(criteriosDeBusquedaProvider).texto;
  }

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _buscar(String texto, {bool yaMismo = false}) {
    _espera?.cancel();
    void aplicar() {
      final criterios = ref.read(criteriosDeBusquedaProvider);
      ref.read(criteriosDeBusquedaProvider.notifier).cambiar(criterios.copiar(texto: texto.trim()));
    }

    // Se espera a que deje de escribir: una búsqueda por pulsación saturaría la API.
    if (yaMismo) {
      aplicar();
    } else {
      _espera = Timer(const Duration(milliseconds: 400), aplicar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final criterios = ref.watch(criteriosDeBusquedaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Licitaciones'), actions: const [BotonDeCuenta()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _texto,
              hintText: 'Buscar por título, órgano o CPV',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              side: WidgetStatePropertyAll(BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              textInputAction: TextInputAction.search,
              onChanged: _buscar,
              onSubmitted: (texto) => _buscar(texto, yaMismo: true),
              trailing: [
                if (_texto.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Borrar la búsqueda',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _texto.clear();
                      _buscar('', yaMismo: true);
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('Solo con plazo abierto'),
                  selected: criterios.soloAbiertas,
                  onSelected: (valor) =>
                      ref.read(criteriosDeBusquedaProvider.notifier).cambiar(criterios.copiar(soloAbiertas: valor)),
                ),
                const SizedBox(width: 8),
                _MenuDeOrden(criterios: criterios),
              ],
            ),
          ),
          const Expanded(child: _Resultados()),
        ],
      ),
    );
  }
}

class _MenuDeOrden extends ConsumerWidget {
  const _MenuDeOrden({required this.criterios});

  final Criterios criterios;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MenuAnchor(
    builder: (context, controlador, _) => ActionChip(
      avatar: const Icon(Icons.sort, size: 18),
      label: Text(criterios.orden.nombre),
      tooltip: 'Ordenar',
      onPressed: () => controlador.isOpen ? controlador.close() : controlador.open(),
    ),
    menuChildren: [
      for (final orden in Orden.values)
        MenuItemButton(
          leadingIcon: Icon(orden == criterios.orden ? Icons.check : null),
          onPressed: () => ref.read(criteriosDeBusquedaProvider.notifier).cambiar(criterios.copiar(orden: orden)),
          child: Text(orden.nombre),
        ),
    ],
  );
}

class _Resultados extends ConsumerWidget {
  const _Resultados();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busqueda = ref.watch(busquedaProvider);
    final etapas = {
      for (final s in ref.watch(seguimientosProvider).value ?? const <SeguimientoLocal>[])
        s.licitacionId: s.seguimiento.etapa,
    };
    return switch (busqueda) {
      AsyncValue(:final value?) when value.licitaciones.isEmpty => const Vacio(
        icono: Icons.search_off,
        titulo: 'Ninguna licitación encaja',
        texto: 'Prueba con otras palabras o quita el filtro de plazo abierto.',
      ),
      AsyncValue(:final value?) => RefreshIndicator(
        onRefresh: () => ref.refresh(busquedaProvider.future),
        child: NotificationListener<ScrollNotification>(
          onNotification: (aviso) {
            if (aviso.metrics.extentAfter < 600) unawaited(ref.read(busquedaProvider.notifier).cargarMas());
            return false;
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: value.licitaciones.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) return _Total(total: value.total);
              final l = value.licitaciones[i - 1];
              return TarjetaDeLicitacion(
                licitacion: l,
                etapa: etapas[l.id],
                alTocar: () => RutaFicha(id: l.id).push<void>(context),
              );
            },
          ),
        ),
      ),
      AsyncValue(:final error?) => ErrorConReintento(error: error, reintentar: () => ref.invalidate(busquedaProvider)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) => Text(
    total == 1 ? '1 licitación' : '$total licitaciones',
    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.estados.textoSuave),
  );
}
