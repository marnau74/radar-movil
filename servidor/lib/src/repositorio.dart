import 'package:mongo_dart/mongo_dart.dart';

import 'package:servidor/src/dominio.dart';

/// Ya existe un seguimiento de esa licitación, o se ha modificado desde que se leyó. Se responde con un 409 y lo
/// guardado, para que la app enseñe el conflicto en vez de pisar un cambio.
class Conflicto implements Exception {
  Conflicto(this.mensaje, this.actual);

  final String mensaje;
  final Seguimiento? actual;
}

/// Seguimientos en MongoDB: un documento por usuario y licitación, con su historial de etapas dentro.
///
/// Todas las consultas filtran por usuario: es lo que impide ver lo de otro. Ojo con `mongo_dart`: una escritura
/// que choca con un índice único no lanza, devuelve el error en el resultado, así que se comprueba siempre.
class RepositorioDeSeguimientos {
  RepositorioDeSeguimientos(this._db, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  static const coleccion = 'seguimientos';
  static const _claveDuplicada = 11000;

  final Db _db;
  final DateTime Function() _reloj;

  DbCollection get _c => _db.collection(coleccion);

  /// Crea los índices (idempotente): uno único por usuario y licitación, y el del embudo.
  Future<void> prepararIndices() async {
    await _db.createIndex(coleccion, keys: {'usuario': 1, 'licitacionId': 1}, unique: true, name: 'usuario_licitacion');
    await _db.createIndex(coleccion, keys: {'usuario': 1, 'etapa': 1, 'resumen.plazo': 1}, name: 'embudo');
  }

  Future<List<Seguimiento>> deUsuario(String usuario, {Etapa? etapa}) async {
    var filtro = where.eq('usuario', usuario);
    if (etapa != null) filtro = filtro.eq('etapa', etapa.name);
    final documentos = await _c.find(filtro.sortBy('resumen.plazo').sortBy('licitacionId')).toList();
    return documentos.map(_leer).toList();
  }

  Future<Seguimiento?> uno(String usuario, int licitacionId) async {
    final documento = await _c.findOne(where.eq('usuario', usuario).eq('licitacionId', licitacionId));
    return documento == null ? null : _leer(documento);
  }

  /// Crea (sin versión) o modifica (con la versión que se editó) el seguimiento.
  Future<Seguimiento> guardar(String usuario, int licitacionId, CambioDeSeguimiento cambio) async {
    final ahora = _reloj().toUtc();
    if (cambio.version == null) {
      final documento = {
        'usuario': usuario,
        'licitacionId': licitacionId,
        'resumen': _resumen(cambio.resumen),
        'etapa': cambio.etapa.name,
        'notas': cambio.notas,
        'responsable': cambio.responsable,
        'fechaInterna': cambio.fechaInterna,
        'historial': [
          {'de': null, 'a': cambio.etapa.name, 'en': ahora},
        ],
        'version': 1,
        'creadoEn': ahora,
        'actualizadoEn': ahora,
      };
      final resultado = await _c.insertOne(documento);
      if (resultado.hasWriteErrors) {
        if (resultado.writeError?.code == _claveDuplicada) {
          throw Conflicto('Ya sigues esta licitación', await uno(usuario, licitacionId));
        }
        throw StateError('MongoDB no ha guardado el seguimiento: ${resultado.writeError?.errmsg}');
      }
      return (await uno(usuario, licitacionId))!;
    }

    final actual = await uno(usuario, licitacionId);
    if (actual == null) throw Conflicto('Este seguimiento ya no existe', null);
    var modificacion = modify
        .set('resumen', _resumen(cambio.resumen))
        .set('etapa', cambio.etapa.name)
        .set('notas', cambio.notas)
        .set('responsable', cambio.responsable)
        .set('fechaInterna', cambio.fechaInterna)
        .set('actualizadoEn', ahora)
        .inc('version', 1);
    if (actual.etapa != cambio.etapa) {
      modificacion = modificacion.push('historial', {'de': actual.etapa.name, 'a': cambio.etapa.name, 'en': ahora});
    }
    // La condición de versión va en el propio filtro: si otro dispositivo ha guardado entre la lectura y esta
    // escritura, no se modifica nada.
    final resultado = await _c.updateOne(
      where.eq('usuario', usuario).eq('licitacionId', licitacionId).eq('version', cambio.version),
      modificacion,
    );
    if (resultado.hasWriteErrors) {
      throw StateError('MongoDB no ha guardado el cambio: ${resultado.writeError?.errmsg}');
    }
    if (resultado.nModified == 0) {
      throw Conflicto('Lo ha cambiado otro dispositivo: revisa la versión guardada', await uno(usuario, licitacionId));
    }
    return (await uno(usuario, licitacionId))!;
  }

  Future<bool> borrar(String usuario, int licitacionId) async {
    final resultado = await _c.deleteOne(where.eq('usuario', usuario).eq('licitacionId', licitacionId));
    return resultado.nRemoved > 0;
  }

  /// Cuántas licitaciones y cuánto importe hay en cada etapa, calculado en MongoDB.
  Future<Embudo> embudo(String usuario) async {
    final filas = await _c.aggregateToStream([
      {
        r'$match': {'usuario': usuario},
      },
      {
        r'$group': {
          '_id': r'$etapa',
          'cuantas': {r'$sum': 1},
          'importe': {
            r'$sum': {
              r'$ifNull': [r'$resumen.importe', 0],
            },
          },
        },
      },
    ]).toList();
    return Embudo({
      for (final fila in filas)
        ?Etapa.deTexto(fila['_id'] as String?): (
          cuantas: (fila['cuantas'] as num).toInt(),
          importe: (fila['importe'] as num).toDouble(),
        ),
    });
  }

  Map<String, dynamic> _resumen(ResumenDeLicitacion r) => {
    'titulo': r.titulo,
    'organo': r.organo,
    'expediente': r.expediente,
    'importe': r.importe,
    'plazo': r.plazo,
  };

  Seguimiento _leer(Map<String, dynamic> d) {
    final resumen = d['resumen'] as Map<String, dynamic>;
    return Seguimiento(
      usuario: d['usuario'] as String,
      licitacionId: (d['licitacionId'] as num).toInt(),
      resumen: ResumenDeLicitacion(
        titulo: resumen['titulo'] as String,
        organo: resumen['organo'] as String,
        expediente: resumen['expediente'] as String?,
        importe: (resumen['importe'] as num?)?.toDouble(),
        plazo: (resumen['plazo'] as DateTime?)?.toUtc(),
      ),
      etapa: Etapa.deTexto(d['etapa'] as String?) ?? Etapa.interesa,
      notas: d['notas'] as String? ?? '',
      responsable: d['responsable'] as String?,
      fechaInterna: (d['fechaInterna'] as DateTime?)?.toUtc(),
      historial: [
        for (final c in (d['historial'] as List? ?? const []).cast<Map<String, dynamic>>())
          CambioDeEtapa(
            de: Etapa.deTexto(c['de'] as String?),
            a: Etapa.deTexto(c['a'] as String?) ?? Etapa.interesa,
            en: (c['en'] as DateTime).toUtc(),
          ),
      ],
      version: (d['version'] as num).toInt(),
      creadoEn: (d['creadoEn'] as DateTime).toUtc(),
      actualizadoEn: (d['actualizadoEn'] as DateTime).toUtc(),
    );
  }
}
