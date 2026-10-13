import 'package:freezed_annotation/freezed_annotation.dart';

part 'licitacion.freezed.dart';
part 'licitacion.g.dart';

/// Una licitación en una lista de resultados del radar (`GET /api/v1/licitaciones`).
@freezed
abstract class LicitacionResumen with _$LicitacionResumen {
  const factory LicitacionResumen({
    required int id,
    required String titulo,
    required String estado,
    required String organo,
    String? expediente,
    double? importeSinIva,
    DateTime? plazoPresentacion,
    DateTime? fechaPublicacion,
    String? lugar,
    @Default(0) int numLotes,
    @Default(false) bool financiacionUe,
    @Default(false) bool anulada,
  }) = _LicitacionResumen;

  factory LicitacionResumen.fromJson(Map<String, dynamic> json) => _$LicitacionResumenFromJson(json);
}

/// Una página de resultados. El radar numera las páginas desde 1.
@freezed
abstract class PaginaDeLicitaciones with _$PaginaDeLicitaciones {
  const factory PaginaDeLicitaciones({
    required List<LicitacionResumen> elementos,
    required int pagina,
    required int tamano,
    required int total,
    required int paginas,
  }) = _PaginaDeLicitaciones;

  const PaginaDeLicitaciones._();

  factory PaginaDeLicitaciones.fromJson(Map<String, dynamic> json) => _$PaginaDeLicitacionesFromJson(json);

  bool get hayMas => pagina < paginas;
}

/// Un código de la Plataforma con su nombre ya traducido por el radar.
@freezed
abstract class Codigo with _$Codigo {
  const factory Codigo({required String codigo, required String nombre}) = _Codigo;

  factory Codigo.fromJson(Map<String, dynamic> json) => _$CodigoFromJson(json);
}

@freezed
abstract class OrganoDeLaFicha with _$OrganoDeLaFicha {
  const factory OrganoDeLaFicha({required int id, required String nombre, String? ciudad, String? perfilContratante}) =
      _OrganoDeLaFicha;

  factory OrganoDeLaFicha.fromJson(Map<String, dynamic> json) => _$OrganoDeLaFichaFromJson(json);
}

@freezed
abstract class Lote with _$Lote {
  const factory Lote({required String numero, String? objeto, double? importeSinIva}) = _Lote;

  factory Lote.fromJson(Map<String, dynamic> json) => _$LoteFromJson(json);
}

@freezed
abstract class Resultado with _$Resultado {
  const factory Resultado({
    String? lote,
    Codigo? resultado,
    DateTime? fechaAdjudicacion,
    int? ofertasRecibidas,
    String? adjudicatario,
    double? importeSinIva,
  }) = _Resultado;

  factory Resultado.fromJson(Map<String, dynamic> json) => _$ResultadoFromJson(json);
}

@freezed
abstract class Documento with _$Documento {
  const factory Documento({required String tipo, required String url, String? nombre}) = _Documento;

  const Documento._();

  factory Documento.fromJson(Map<String, dynamic> json) => _$DocumentoFromJson(json);

  String get descripcion => switch (tipo) {
    'PLIEGO_ADMINISTRATIVO' => 'Pliego de cláusulas administrativas',
    'PLIEGO_TECNICO' => 'Pliego de prescripciones técnicas',
    _ => nombre ?? 'Documento',
  };
}

/// La ficha de una licitación (`GET /api/v1/licitaciones/{id}`). Solo lo que enseña la app.
@freezed
abstract class FichaDeLicitacion with _$FichaDeLicitacion {
  const factory FichaDeLicitacion({
    required int id,
    required String titulo,
    required Codigo estado,
    required OrganoDeLaFicha organo,
    String? expediente,
    String? url,
    Codigo? tipoContrato,
    Codigo? procedimiento,
    double? importeSinIva,
    double? importeConIva,
    double? valorEstimado,
    @Default([]) List<Codigo> cpv,
    String? lugar,
    DateTime? plazoPresentacion,
    DateTime? fechaPublicacion,
    String? duracion,
    @Default(false) bool financiacionUe,
    @Default(false) bool anulada,
    @Default([]) List<Lote> lotes,
    @Default([]) List<Resultado> resultados,
    @Default([]) List<Documento> documentos,
  }) = _FichaDeLicitacion;

  factory FichaDeLicitacion.fromJson(Map<String, dynamic> json) => _$FichaDeLicitacionFromJson(json);
}

/// Lo que ha encontrado una alerta del radar (`GET /api/v1/avisos`).
@freezed
abstract class AvisoDelRadar with _$AvisoDelRadar {
  const factory AvisoDelRadar({
    required int id,
    required String alerta,
    required DateTime creadoEn,
    required bool leido,
    required LicitacionResumen licitacion,
  }) = _AvisoDelRadar;

  factory AvisoDelRadar.fromJson(Map<String, dynamic> json) => _$AvisoDelRadarFromJson(json);
}

@freezed
abstract class PaginaDeAvisos with _$PaginaDeAvisos {
  const factory PaginaDeAvisos({
    required List<AvisoDelRadar> elementos,
    required int pagina,
    required int total,
    required int paginas,
  }) = _PaginaDeAvisos;

  factory PaginaDeAvisos.fromJson(Map<String, dynamic> json) => _$PaginaDeAvisosFromJson(json);
}
