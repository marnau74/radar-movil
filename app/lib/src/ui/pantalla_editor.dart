import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radar_movil/src/datos/repositorio_de_seguimiento.dart';
import 'package:radar_movil/src/estado.dart';
import 'package:radar_movil/src/ui/comunes.dart';
import 'package:radar_movil/src/ui/formato.dart';

/// Las notas, el responsable y la fecha límite interna de un seguimiento. Los límites son los mismos que valida el
/// servidor, para que un cambio guardado sin red no se rechace después.
class PantallaEditor extends ConsumerWidget {
  const PantallaEditor({required this.id, super.key});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(seguimientoDeProvider(id));
    return switch (local) {
      AsyncValue(value: final SeguimientoLocal s) when !s.enConflicto => _Formulario(local: s),
      AsyncValue(hasValue: true) => Scaffold(
        appBar: AppBar(),
        body: const Vacio(
          icono: Icons.bookmark_border,
          titulo: 'No se puede editar',
          texto: 'Ya no sigues esta licitación o hay un conflicto pendiente de resolver en su ficha.',
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({required this.local});

  final SeguimientoLocal local;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  static const maxNotas = 5000;
  static const maxResponsable = 100;

  final _clave = GlobalKey<FormState>();
  late final _notas = TextEditingController(text: widget.local.seguimiento.notas);
  late final _responsable = TextEditingController(text: widget.local.seguimiento.responsable ?? '');
  late DateTime? _fechaInterna = widget.local.seguimiento.fechaInterna?.toLocal();
  bool _guardando = false;

  @override
  void dispose() {
    _notas.dispose();
    _responsable.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final hoy = ref.read(relojProvider)();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaInterna ?? hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 3),
      helpText: 'Fecha límite interna',
    );
    if (elegida != null) setState(() => _fechaInterna = elegida);
  }

  Future<void> _guardar() async {
    if (!_clave.currentState!.validate()) return;
    setState(() => _guardando = true);
    final responsable = _responsable.text.trim();
    final cambiado = widget.local.seguimiento.copyWith(
      notas: _notas.text.trim(),
      responsable: responsable.isEmpty ? null : responsable,
      fechaInterna: _fechaInterna == null
          ? null
          : DateTime(_fechaInterna!.year, _fechaInterna!.month, _fechaInterna!.day, 12).toUtc(),
    );
    final navegador = Navigator.of(context);
    final mensajero = ScaffoldMessenger.of(context);
    try {
      await ref.read(sincronizacionProvider.notifier).guardar(cambiado);
      navegador.pop();
    } on Object catch (error) {
      mensajero.showSnackBar(SnackBar(content: Text(mensajeDeError(error))));
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumen = widget.local.seguimiento.resumen;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar seguimiento'),
        leading: const CloseButton(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
          ),
        ],
      ),
      body: Form(
        key: _clave,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(resumen.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 20),
            TextFormField(
              controller: _responsable,
              decoration: const InputDecoration(labelText: 'Responsable', hintText: 'Quién prepara la oferta'),
              textCapitalization: TextCapitalization.words,
              maxLength: maxResponsable,
              validator: (v) =>
                  (v ?? '').trim().length > maxResponsable ? 'Como mucho $maxResponsable caracteres' : null,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Fecha límite interna',
                helperText: 'Avisa a las 9:00 de ese día. Antes del plazo oficial (${fechaHora(resumen.plazo)}).',
                helperMaxLines: 2,
                suffixIcon: _fechaInterna == null
                    ? null
                    : IconButton(
                        tooltip: 'Quitar la fecha',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _fechaInterna = null),
                      ),
              ),
              child: InkWell(
                onTap: _elegirFecha,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(_fechaInterna == null ? 'Sin fecha' : fecha(_fechaInterna)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notas,
              decoration: const InputDecoration(labelText: 'Notas', alignLabelWithHint: true),
              minLines: 6,
              maxLines: 14,
              maxLength: maxNotas,
              keyboardType: TextInputType.multiline,
              validator: (v) => (v ?? '').length > maxNotas ? 'Como mucho $maxNotas caracteres' : null,
            ),
          ],
        ),
      ),
    );
  }
}
