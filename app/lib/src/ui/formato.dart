import 'package:intl/intl.dart';

final _euros = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 2);
final _eurosRedondos = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 0);
final _fecha = DateFormat('d MMM y', 'es_ES');
final _fechaHora = DateFormat('d MMM y, HH:mm', 'es_ES');
final _porcentaje = NumberFormat.percentPattern('es_ES');

/// `47.775,00 €`; sin céntimos si es un número redondo.
String euros(double? importe) {
  if (importe == null) return 'Sin importe';
  return importe == importe.roundToDouble() ? _eurosRedondos.format(importe) : _euros.format(importe);
}

String fecha(DateTime? valor) => valor == null ? '—' : _fecha.format(valor.toLocal());

String fechaHora(DateTime? valor) => valor == null ? '—' : _fechaHora.format(valor.toLocal());

String porcentaje(double valor) => _porcentaje.format(valor);

/// Cuánto le queda al plazo de presentación.
enum Urgencia { sinPlazo, cerrado, hoy, pronto, holgado }

({String texto, Urgencia urgencia}) plazoRestante(DateTime? plazo, DateTime momento) {
  if (plazo == null) return (texto: 'Sin plazo publicado', urgencia: Urgencia.sinPlazo);
  final local = plazo.toLocal();
  final ahora = momento.toLocal();
  if (!local.isAfter(ahora)) return (texto: 'Plazo cerrado', urgencia: Urgencia.cerrado);
  // Días de calendario, contados en UTC para que un cambio de hora no reste un día.
  final hoy = DateTime.utc(ahora.year, ahora.month, ahora.day);
  final dias = DateTime.utc(local.year, local.month, local.day).difference(hoy).inDays;
  final hora = DateFormat('HH:mm').format(local);
  return switch (dias) {
    0 => (texto: 'Cierra hoy a las $hora', urgencia: Urgencia.hoy),
    1 => (texto: 'Cierra mañana a las $hora', urgencia: Urgencia.pronto),
    < 4 => (texto: 'Cierra en $dias días', urgencia: Urgencia.pronto),
    _ => (texto: 'Cierra el ${_fecha.format(local)}', urgencia: Urgencia.holgado),
  };
}
