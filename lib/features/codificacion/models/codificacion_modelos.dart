// Modelos del módulo de Codificación.

class ErrorNegocioCodificacion implements Exception {
  final String mensaje;
  const ErrorNegocioCodificacion(this.mensaje);
  @override
  String toString() => mensaje;
}

class Sabor {
  final int id;
  final String nombre;
  const Sabor({required this.id, required this.nombre});
  factory Sabor.fromMap(Map<String, dynamic> m) =>
      Sabor(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

class Presentacion {
  final int id;
  final String nombre;
  final String material;
  const Presentacion({required this.id, required this.nombre, required this.material});
  factory Presentacion.fromMap(Map<String, dynamic> m) => Presentacion(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
        material: m['material'] as String,
      );
}

/// Corrida de Llenadora que se puede vincular (opcional), para trazabilidad.
class CorridaLlenadoraRef {
  final int id;
  final int saborId;
  final String turno;
  const CorridaLlenadoraRef({required this.id, required this.saborId, required this.turno});
  factory CorridaLlenadoraRef.fromMap(Map<String, dynamic> m) => CorridaLlenadoraRef(
        id: (m['id'] as num).toInt(),
        saborId: (m['sabor_id'] as num).toInt(),
        turno: m['turno'] as String,
      );
}

/// Ítem del catálogo (solvente o tinta) para descontar en el reporte.
class ItemInventario {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  const ItemInventario(
      {required this.id, required this.codigo, required this.detalle, required this.unidad});
  factory ItemInventario.fromMap(Map<String, dynamic> m) => ItemInventario(
        id: (m['id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
      );
}

enum Turno {
  manana('manana', 'Mañana'),
  tarde('tarde', 'Tarde'),
  noche('noche', 'Noche');

  final String id;
  final String etiqueta;
  const Turno(this.id, this.etiqueta);
  static Turno desde(String id) => values.firstWhere((t) => t.id == id, orElse: () => Turno.manana);
}

enum EstadoCorrida {
  enCurso('en_curso', 'En curso'),
  finalizada('finalizada', 'Finalizada'),
  anulada('anulada', 'Anulada');

  final String id;
  final String etiqueta;
  const EstadoCorrida(this.id, this.etiqueta);
  static EstadoCorrida desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoCorrida.enCurso);
}

class CorridaCodificacion {
  final int id;
  final DateTime fecha;
  final Turno turno;
  final int saborId;
  final String? sabor;
  final int presentacionId;
  final String? presentacion;
  final int? corridaLlenadoraId;
  final String? nLote;
  final EstadoCorrida estado;
  final DateTime horaInicio;
  final DateTime? horaFin;
  final double? botellasCodificadas;
  final String? codigoImpreso;
  final double botellasMalTapadas;
  final double tapasMalTapadas;
  final double impurezas;
  final String? motivoMerma;
  final int? itemSolventeId;
  final String? itemSolventeDetalle;
  final double solventeUsado;
  final int? itemTintaId;
  final String? itemTintaDetalle;
  final double tintaUsada;
  final String? observaciones;
  final String? responsableNombre;

  const CorridaCodificacion({
    required this.id,
    required this.fecha,
    required this.turno,
    required this.saborId,
    this.sabor,
    required this.presentacionId,
    this.presentacion,
    this.corridaLlenadoraId,
    this.nLote,
    required this.estado,
    required this.horaInicio,
    this.horaFin,
    this.botellasCodificadas,
    this.codigoImpreso,
    this.botellasMalTapadas = 0,
    this.tapasMalTapadas = 0,
    this.impurezas = 0,
    this.motivoMerma,
    this.itemSolventeId,
    this.itemSolventeDetalle,
    this.solventeUsado = 0,
    this.itemTintaId,
    this.itemTintaDetalle,
    this.tintaUsada = 0,
    this.observaciones,
    this.responsableNombre,
  });

  Duration? get duracion => horaFin?.difference(horaInicio);

  /// Iniciado sin internet y todavía en la cola (id provisorio negativo).
  bool get sinSubir => id < 0;
  bool get tieneMerma => botellasMalTapadas > 0 || tapasMalTapadas > 0 || impurezas > 0;
  double? get botellasBuenas =>
      botellasCodificadas == null ? null : botellasCodificadas! - botellasMalTapadas;

  factory CorridaCodificacion.fromMap(Map<String, dynamic> m) {
    final sabor = m['sabores'] as Map?;
    final presentacion = m['presentaciones'] as Map?;
    final solvente = m['solvente'] as Map?;
    final tinta = m['tinta'] as Map?;
    return CorridaCodificacion(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String),
      turno: Turno.desde(m['turno'] as String),
      saborId: (m['sabor_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      presentacionId: (m['presentacion_id'] as num).toInt(),
      presentacion: presentacion?['nombre'] as String?,
      corridaLlenadoraId: (m['corrida_llenadora_id'] as num?)?.toInt(),
      nLote: m['n_lote'] as String?,
      estado: EstadoCorrida.desde(m['estado'] as String),
      horaInicio: DateTime.parse(m['hora_inicio'] as String).toLocal(),
      horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
      botellasCodificadas: (m['botellas_codificadas'] as num?)?.toDouble(),
      codigoImpreso: m['codigo_impreso'] as String?,
      botellasMalTapadas: (m['botellas_mal_tapadas'] as num?)?.toDouble() ?? 0,
      tapasMalTapadas: (m['tapas_mal_tapadas'] as num?)?.toDouble() ?? 0,
      impurezas: (m['impurezas'] as num?)?.toDouble() ?? 0,
      motivoMerma: m['motivo_merma'] as String?,
      itemSolventeId: (m['item_solvente_id'] as num?)?.toInt(),
      itemSolventeDetalle: solvente?['detalle'] as String?,
      solventeUsado: (m['solvente_usado'] as num?)?.toDouble() ?? 0,
      itemTintaId: (m['item_tinta_id'] as num?)?.toInt(),
      itemTintaDetalle: tinta?['detalle'] as String?,
      tintaUsada: (m['tinta_usada'] as num?)?.toDouble() ?? 0,
      observaciones: m['observaciones'] as String?,
      responsableNombre: m['responsable_nombre'] as String?,
    );
  }
}

class AvanceCodificacion {
  final String sabor;
  final String presentacion;
  final int corridas;
  final double botellasBuenas;
  final DateTime? ultimaCorrida;

  const AvanceCodificacion({
    required this.sabor,
    required this.presentacion,
    required this.corridas,
    required this.botellasBuenas,
    this.ultimaCorrida,
  });

  factory AvanceCodificacion.fromMap(Map<String, dynamic> m) => AvanceCodificacion(
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String,
        corridas: (m['corridas'] as num).toInt(),
        botellasBuenas: (m['botellas_buenas'] as num).toDouble(),
        ultimaCorrida: m['ultima_corrida'] == null
            ? null
            : DateTime.parse(m['ultima_corrida'] as String).toLocal(),
      );
}

class FinalizarCorridaCodificacion {
  final double botellasCodificadas;
  final String? codigoImpreso;
  final double botellasMalTapadas;
  final double tapasMalTapadas;
  final double impurezas;
  final String? motivoMerma;
  final double solventeUsado;
  final double tintaUsada;
  final String? observaciones;

  const FinalizarCorridaCodificacion({
    required this.botellasCodificadas,
    this.codigoImpreso,
    this.botellasMalTapadas = 0,
    this.tapasMalTapadas = 0,
    this.impurezas = 0,
    this.motivoMerma,
    this.solventeUsado = 0,
    this.tintaUsada = 0,
    this.observaciones,
  });
}
