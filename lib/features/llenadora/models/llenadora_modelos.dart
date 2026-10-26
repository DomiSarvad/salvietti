// Modelos del módulo de Llenadora.

class ErrorNegocioLlenadora implements Exception {
  final String mensaje;
  const ErrorNegocioLlenadora(this.mensaje);
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

/// Preparado de Jarabes que se puede vincular a una corrida (opcional).
class PreparadoJarabes {
  final int id;
  final int saborId;
  final int nLote;
  final int? tanque;
  const PreparadoJarabes(
      {required this.id, required this.saborId, required this.nLote, this.tanque});
  factory PreparadoJarabes.fromMap(Map<String, dynamic> m) => PreparadoJarabes(
        id: (m['id'] as num).toInt(),
        saborId: (m['sabor_id'] as num).toInt(),
        nLote: (m['n_lote'] as num).toInt(),
        tanque: (m['tanque'] as num?)?.toInt(),
      );
}

/// Ítem del catálogo (tapa) que se puede elegir para descontar en la corrida.
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

class CorridaLlenadora {
  final int id;
  final DateTime fecha;
  final Turno turno;
  final int saborId;
  final String? sabor;
  final int presentacionId;
  final String? presentacion;
  final int? preparadoId;
  final String? nLotePreparado;
  final String? tanque;
  final EstadoCorrida estado;
  final DateTime horaInicio;
  final DateTime? horaFin;
  final double? botellasLlenadas;
  final double botellasDesechadas;
  final int? itemTapaId;
  final String? itemTapaDetalle;
  final double tapasUsadas;
  final double tapasDesechadas;
  final double rebalse;
  final String? motivoMerma;
  final String? observaciones;
  final String? responsableNombre;

  const CorridaLlenadora({
    required this.id,
    required this.fecha,
    required this.turno,
    required this.saborId,
    this.sabor,
    required this.presentacionId,
    this.presentacion,
    this.preparadoId,
    this.nLotePreparado,
    this.tanque,
    required this.estado,
    required this.horaInicio,
    this.horaFin,
    this.botellasLlenadas,
    this.botellasDesechadas = 0,
    this.itemTapaId,
    this.itemTapaDetalle,
    this.tapasUsadas = 0,
    this.tapasDesechadas = 0,
    this.rebalse = 0,
    this.motivoMerma,
    this.observaciones,
    this.responsableNombre,
  });

  Duration? get duracion => horaFin?.difference(horaInicio);

  /// Iniciado sin internet y todavía en la cola (id provisorio negativo).
  bool get sinSubir => id < 0;
  bool get tieneMerma => botellasDesechadas > 0 || tapasDesechadas > 0 || rebalse > 0;
  double? get botellasBuenas =>
      botellasLlenadas == null ? null : botellasLlenadas! - botellasDesechadas;

  /// Referencia de lote/tanque para mostrar: prioriza el preparado vinculado.
  String get referenciaLote {
    final partes = <String>[
      if (nLotePreparado != null && nLotePreparado!.isNotEmpty) 'Lote $nLotePreparado',
      if (tanque != null && tanque!.isNotEmpty) 'Tanque $tanque',
    ];
    return partes.join(' · ');
  }

  factory CorridaLlenadora.fromMap(Map<String, dynamic> m) {
    final sabor = m['sabores'] as Map?;
    final presentacion = m['presentaciones'] as Map?;
    final tapa = m['inv_items'] as Map?;
    return CorridaLlenadora(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String),
      turno: Turno.desde(m['turno'] as String),
      saborId: (m['sabor_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      presentacionId: (m['presentacion_id'] as num).toInt(),
      presentacion: presentacion?['nombre'] as String?,
      preparadoId: (m['preparado_id'] as num?)?.toInt(),
      nLotePreparado: m['n_lote_preparado'] as String?,
      tanque: m['tanque'] as String?,
      estado: EstadoCorrida.desde(m['estado'] as String),
      horaInicio: DateTime.parse(m['hora_inicio'] as String).toLocal(),
      horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
      botellasLlenadas: (m['botellas_llenadas'] as num?)?.toDouble(),
      botellasDesechadas: (m['botellas_desechadas'] as num?)?.toDouble() ?? 0,
      itemTapaId: (m['item_tapa_id'] as num?)?.toInt(),
      itemTapaDetalle: tapa?['detalle'] as String?,
      tapasUsadas: (m['tapas_usadas'] as num?)?.toDouble() ?? 0,
      tapasDesechadas: (m['tapas_desechadas'] as num?)?.toDouble() ?? 0,
      rebalse: (m['rebalse'] as num?)?.toDouble() ?? 0,
      motivoMerma: m['motivo_merma'] as String?,
      observaciones: m['observaciones'] as String?,
      responsableNombre: m['responsable_nombre'] as String?,
    );
  }
}

/// Avance de los últimos 14 días, por sabor y presentación.
class AvanceLlenadora {
  final String sabor;
  final String presentacion;
  final int corridas;
  final double botellasBuenas;
  final DateTime? ultimaCorrida;

  const AvanceLlenadora({
    required this.sabor,
    required this.presentacion,
    required this.corridas,
    required this.botellasBuenas,
    this.ultimaCorrida,
  });

  factory AvanceLlenadora.fromMap(Map<String, dynamic> m) => AvanceLlenadora(
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String,
        corridas: (m['corridas'] as num).toInt(),
        botellasBuenas: (m['botellas_buenas'] as num).toDouble(),
        ultimaCorrida: m['ultima_corrida'] == null
            ? null
            : DateTime.parse(m['ultima_corrida'] as String).toLocal(),
      );
}

class FinalizarCorridaLlenadora {
  final double botellasLlenadas;
  final double botellasDesechadas;
  final double tapasUsadas;
  final double tapasDesechadas;
  final double rebalse;
  final String? motivoMerma;
  final String? observaciones;

  const FinalizarCorridaLlenadora({
    required this.botellasLlenadas,
    this.botellasDesechadas = 0,
    this.tapasUsadas = 0,
    this.tapasDesechadas = 0,
    this.rebalse = 0,
    this.motivoMerma,
    this.observaciones,
  });
}
