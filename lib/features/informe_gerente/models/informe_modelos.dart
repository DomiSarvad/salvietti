// Modelos del Informe general de Producción (Módulo 11).

/// Un problema que tiene un motivo claro para mostrarle a la persona (no
/// "revisá la conexión" cuando el problema es otro).
class ErrorInforme implements Exception {
  final String mensaje;
  const ErrorInforme(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Una fila del resumen: un sabor en un día, lo esperado (de Jarabes ×
/// estándar del sabor) contra lo producido (de Registro de salidas).
class ResumenProduccion {
  final DateTime fecha;
  final int? saborId;
  final String sabor;
  final double? preparados;
  final double? cajasEsperadas;
  final double? cajasProducidas;
  final double? desviacionCajas;
  final double? desviacionPorcentaje;
  final bool datosIncompletos;

  const ResumenProduccion({
    required this.fecha,
    this.saborId,
    required this.sabor,
    this.preparados,
    this.cajasEsperadas,
    this.cajasProducidas,
    this.desviacionCajas,
    this.desviacionPorcentaje,
    this.datosIncompletos = false,
  });

  bool get alertaDesviacion => desviacionPorcentaje != null && desviacionPorcentaje!.abs() > 3;

  factory ResumenProduccion.fromMap(Map<String, dynamic> m) => ResumenProduccion(
        fecha: DateTime.parse(m['fecha'] as String),
        saborId: (m['sabor_id'] as num?)?.toInt(),
        sabor: (m['sabor'] as String?) ?? '—',
        preparados: (m['preparados'] as num?)?.toDouble(),
        cajasEsperadas: (m['cajas_esperadas'] as num?)?.toDouble(),
        cajasProducidas: (m['cajas_producidas'] as num?)?.toDouble(),
        desviacionCajas: (m['desviacion_cajas'] as num?)?.toDouble(),
        desviacionPorcentaje: (m['desviacion_porcentaje'] as num?)?.toDouble(),
        datosIncompletos: m['datos_incompletos'] as bool? ?? false,
      );
}

/// Detalle de merma de un área, para cuando el Gerente hace clic en una
/// fila del resumen (misma forma que `EventoMerma` de Mermas, para no
/// duplicar el modelo se repite acá lo mínimo que usa esta pantalla).
class DetalleMermaArea {
  final String area;
  final double totalMerma;
  final double? porcentaje;
  final bool alerta;
  final String? motivo;

  const DetalleMermaArea({
    required this.area,
    required this.totalMerma,
    this.porcentaje,
    this.alerta = false,
    this.motivo,
  });

  factory DetalleMermaArea.fromMap(Map<String, dynamic> m) => DetalleMermaArea(
        area: m['area'] as String,
        totalMerma: (m['total_merma'] as num).toDouble(),
        porcentaje: (m['porcentaje'] as num?)?.toDouble(),
        alerta: m['alerta'] as bool? ?? false,
        motivo: m['motivo'] as String?,
      );
}
