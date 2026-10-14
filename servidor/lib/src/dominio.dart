/// El seguimiento que una empresa hace de una licitación: en qué etapa está su oferta, sus notas y el historial.
library;

/// Las etapas de una oferta. Las tres últimas cierran el seguimiento.
enum Etapa {
  interesa('Interesa'),
  preparando('Preparando la oferta'),
  presentada('Presentada'),
  ganada('Ganada'),
  perdida('Perdida'),
  descartada('Descartada');

  Etapa(this.nombre);

  final String nombre;

  bool get cerrada => this == ganada || this == perdida || this == descartada;

  static Etapa? deTexto(String? texto) => texto == null ? null : Etapa.values.where((e) => e.name == texto).firstOrNull;
}

/// Un dato que no se acepta. Se responde con un 400 que lo explica.
class DatoNoValido implements Exception {
  DatoNoValido(this.errores);

  final Map<String, String> errores;

  @override
  String toString() => 'DatoNoValido($errores)';
}

/// Lo que se guarda de la licitación para que el embudo funcione sin preguntar al radar.
class ResumenDeLicitacion {
  const ResumenDeLicitacion({required this.titulo, required this.organo, this.expediente, this.importe, this.plazo});

  factory ResumenDeLicitacion.desdeJson(Map<String, dynamic> json) => ResumenDeLicitacion(
    titulo: json['titulo'] as String,
    organo: json['organo'] as String,
    expediente: json['expediente'] as String?,
    importe: (json['importe'] as num?)?.toDouble(),
    plazo: json['plazo'] == null ? null : _fecha(json['plazo']),
  );

  final String titulo;
  final String organo;
  final String? expediente;
  final double? importe;
  final DateTime? plazo;

  Map<String, dynamic> aJson() => {
    'titulo': titulo,
    'organo': organo,
    'expediente': expediente,
    'importe': importe,
    'plazo': plazo?.toUtc().toIso8601String(),
  };
}

class CambioDeEtapa {
  const CambioDeEtapa({required this.de, required this.a, required this.en});

  final Etapa? de;
  final Etapa a;
  final DateTime en;

  Map<String, dynamic> aJson() => {'de': de?.name, 'a': a.name, 'en': en.toUtc().toIso8601String()};
}

/// Un seguimiento guardado.
class Seguimiento {
  const Seguimiento({
    required this.usuario,
    required this.licitacionId,
    required this.resumen,
    required this.etapa,
    required this.notas,
    required this.responsable,
    required this.fechaInterna,
    required this.historial,
    required this.version,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  final String usuario;
  final int licitacionId;
  final ResumenDeLicitacion resumen;
  final Etapa etapa;
  final String notas;
  final String? responsable;

  /// La fecha límite que se pone la propia empresa (antes del plazo oficial, para revisar la oferta).
  final DateTime? fechaInterna;
  final List<CambioDeEtapa> historial;

  /// Sube con cada cambio: un cambio hecho sobre una versión vieja se rechaza (concurrencia optimista).
  final int version;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  /// La representación de la API (sin el usuario: es siempre el de la sesión).
  Map<String, dynamic> aJson() => {
    'licitacionId': licitacionId,
    'resumen': resumen.aJson(),
    'etapa': etapa.name,
    'notas': notas,
    'responsable': responsable,
    'fechaInterna': fechaInterna?.toUtc().toIso8601String(),
    'historial': historial.map((c) => c.aJson()).toList(),
    'version': version,
    'creadoEn': creadoEn.toUtc().toIso8601String(),
    'actualizadoEn': actualizadoEn.toUtc().toIso8601String(),
  };
}

/// Lo que llega en un `PUT`: crear (sin versión) o modificar (con la versión que se editó).
class CambioDeSeguimiento {
  const CambioDeSeguimiento({
    required this.resumen,
    required this.etapa,
    required this.notas,
    required this.responsable,
    required this.fechaInterna,
    required this.version,
  });

  /// Valida todo y reúne todos los errores a la vez, para que la app los enseñe juntos.
  factory CambioDeSeguimiento.validar(Object? cuerpo) {
    if (cuerpo is! Map<String, dynamic>) {
      throw DatoNoValido({'cuerpo': 'Se esperaba un objeto JSON'});
    }
    final errores = <String, String>{};
    final resumen = cuerpo['resumen'];
    ResumenDeLicitacion? resumenLeido;
    if (resumen is! Map<String, dynamic>) {
      errores['resumen'] = 'Falta el resumen de la licitación';
    } else {
      final titulo = resumen['titulo'];
      final organo = resumen['organo'];
      if (titulo is! String || titulo.trim().isEmpty || titulo.length > 1000) {
        errores['resumen.titulo'] = 'El título es obligatorio (como mucho 1.000 caracteres)';
      }
      if (organo is! String || organo.trim().isEmpty || organo.length > 500) {
        errores['resumen.organo'] = 'El órgano es obligatorio (como mucho 500 caracteres)';
      }
      final importe = resumen['importe'];
      if (importe != null && (importe is! num || importe < 0)) {
        errores['resumen.importe'] = 'El importe tiene que ser un número no negativo';
      }
      final expediente = resumen['expediente'];
      if (expediente != null && (expediente is! String || expediente.length > 200)) {
        errores['resumen.expediente'] = 'El expediente es texto (como mucho 200 caracteres)';
      }
      if (resumen['plazo'] != null && _fechaOpcional(resumen['plazo']) == null) {
        errores['resumen.plazo'] = 'El plazo tiene que ser una fecha ISO 8601';
      }
      if (!errores.keys.any((k) => k.startsWith('resumen'))) {
        resumenLeido = ResumenDeLicitacion.desdeJson(resumen);
      }
    }
    final textoDeEtapa = cuerpo['etapa'];
    final etapa = textoDeEtapa is String ? Etapa.deTexto(textoDeEtapa) : null;
    if (etapa == null) {
      errores['etapa'] = 'Etapa no válida: ${Etapa.values.map((e) => e.name).join(', ')}';
    }
    final notas = cuerpo['notas'] ?? '';
    if (notas is! String || notas.length > 5000) {
      errores['notas'] = 'Las notas son texto (como mucho 5.000 caracteres)';
    }
    final responsable = cuerpo['responsable'];
    if (responsable != null && (responsable is! String || responsable.length > 100)) {
      errores['responsable'] = 'El responsable es texto (como mucho 100 caracteres)';
    }
    final fechaInterna = cuerpo['fechaInterna'];
    if (fechaInterna != null && _fechaOpcional(fechaInterna) == null) {
      errores['fechaInterna'] = 'La fecha interna tiene que ser una fecha ISO 8601';
    }
    final version = cuerpo['version'];
    if (version != null && (version is! int || version < 1)) {
      errores['version'] = 'La versión es un entero positivo';
    }
    if (errores.isNotEmpty) throw DatoNoValido(errores);
    return CambioDeSeguimiento(
      resumen: resumenLeido!,
      etapa: etapa!,
      notas: (notas as String).trim(),
      responsable: (responsable as String?)?.trim().isEmpty ?? true ? null : (responsable!).trim(),
      fechaInterna: fechaInterna == null ? null : _fecha(fechaInterna),
      version: version as int?,
    );
  }

  final ResumenDeLicitacion resumen;
  final Etapa etapa;
  final String notas;
  final String? responsable;
  final DateTime? fechaInterna;
  final int? version;
}

/// Las cifras del embudo de un usuario.
class Embudo {
  const Embudo(this.porEtapa);

  final Map<Etapa, ({int cuantas, double importe})> porEtapa;

  /// Ofertas ganadas entre las resueltas (ganadas y perdidas); nula si aún no hay ninguna resuelta.
  double? get tasaDeExito {
    final ganadas = porEtapa[Etapa.ganada]?.cuantas ?? 0;
    final perdidas = porEtapa[Etapa.perdida]?.cuantas ?? 0;
    return ganadas + perdidas == 0 ? null : ganadas / (ganadas + perdidas);
  }

  Map<String, dynamic> aJson() => {
    'etapas': [
      for (final etapa in Etapa.values)
        {
          'etapa': etapa.name,
          'nombre': etapa.nombre,
          'cuantas': porEtapa[etapa]?.cuantas ?? 0,
          'importe': porEtapa[etapa]?.importe ?? 0,
        },
    ],
    'tasaDeExito': tasaDeExito,
  };
}

DateTime _fecha(Object? valor) => valor is DateTime ? valor.toUtc() : DateTime.parse(valor! as String).toUtc();

DateTime? _fechaOpcional(Object? valor) {
  if (valor is! String) return null;
  return DateTime.tryParse(valor)?.toUtc();
}
