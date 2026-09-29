// Modelos del módulo de Control de Calidad.

class ErrorNegocioCalidad implements Exception {
  final String mensaje;
  const ErrorNegocioCalidad(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Un preparado de Jarabes finalizado que todavía no tiene análisis.
class PreparadoPendiente {
  final int preparadoId;
  final DateTime fecha;
  final String sabor;
  final int nLote;
  final int? tanque;
  final double cantidadPreparados;
  final double? litros;
  final double? brix;
  final DateTime? horaFin;
  final double? brixMin;
  final double? brixMax;

  const PreparadoPendiente({
    required this.preparadoId,
    required this.fecha,
    required this.sabor,
    required this.nLote,
    this.tanque,
    required this.cantidadPreparados,
    this.litros,
    this.brix,
    this.horaFin,
    this.brixMin,
    this.brixMax,
  });

  /// El Brix que midió Jarabes está fuera del rango objetivo del sabor
  /// (solo si el sabor tiene un rango cargado).
  bool get brixFueraDeRango {
    if (brix == null) return false;
    if (brixMin != null && brix! < brixMin!) return true;
    if (brixMax != null && brix! > brixMax!) return true;
    return false;
  }

  factory PreparadoPendiente.fromMap(Map<String, dynamic> m) => PreparadoPendiente(
        preparadoId: (m['preparado_id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String),
        sabor: m['sabor'] as String,
        nLote: (m['n_lote'] as num).toInt(),
        tanque: (m['tanque'] as num?)?.toInt(),
        cantidadPreparados: (m['cantidad_preparados'] as num).toDouble(),
        litros: (m['litros'] as num?)?.toDouble(),
        brix: (m['brix'] as num?)?.toDouble(),
        horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
        brixMin: (m['brix_min'] as num?)?.toDouble(),
        brixMax: (m['brix_max'] as num?)?.toDouble(),
      );
}

class AnalisisCalidad {
  final int id;
  final int preparadoId;
  final String? sabor;
  final int? nLote;
  final DateTime fecha;
  final double? brixDiluido;
  final double? ph;
  final String? aspecto;
  final String resultado; // 'conforme' | 'no_conforme'
  final String? accionTomada;
  final String? observaciones;
  final String? responsableNombre;

  const AnalisisCalidad({
    required this.id,
    required this.preparadoId,
    this.sabor,
    this.nLote,
    required this.fecha,
    this.brixDiluido,
    this.ph,
    this.aspecto,
    required this.resultado,
    this.accionTomada,
    this.observaciones,
    this.responsableNombre,
  });

  bool get conforme => resultado == 'conforme';

  factory AnalisisCalidad.fromMap(Map<String, dynamic> m) {
    final preparado = m['jarabes_preparados'] as Map?;
    final sabor = preparado?['sabores'] as Map?;
    return AnalisisCalidad(
      id: (m['id'] as num).toInt(),
      preparadoId: (m['preparado_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      nLote: (preparado?['n_lote'] as num?)?.toInt(),
      fecha: DateTime.parse(m['fecha'] as String).toLocal(),
      brixDiluido: (m['brix_diluido'] as num?)?.toDouble(),
      ph: (m['ph'] as num?)?.toDouble(),
      aspecto: m['aspecto'] as String?,
      resultado: m['resultado'] as String,
      accionTomada: m['accion_tomada'] as String?,
      observaciones: m['observaciones'] as String?,
      responsableNombre: m['responsable_nombre'] as String?,
    );
  }
}

class NuevoAnalisis {
  final int preparadoId;
  final double? brixDiluido;
  final double? ph;
  final String resultado;
  final String? aspecto;
  final String? accionTomada;
  final String? observaciones;

  const NuevoAnalisis({
    required this.preparadoId,
    this.brixDiluido,
    this.ph,
    required this.resultado,
    this.aspecto,
    this.accionTomada,
    this.observaciones,
  });
}
