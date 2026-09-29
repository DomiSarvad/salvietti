// Modelos del módulo de Registro de salidas (reporte diario de producción).

class ErrorNegocioSalidas implements Exception {
  final String mensaje;
  const ErrorNegocioSalidas(this.mensaje);
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
  bool get esPet => material == 'pet';
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

enum EstadoReporte {
  abierto('abierto', 'Abierto'),
  cerrado('cerrado', 'Cerrado');

  final String id;
  final String etiqueta;
  const EstadoReporte(this.id, this.etiqueta);
  static EstadoReporte desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoReporte.abierto);
}

class ReporteSalidas {
  final int id;
  final DateTime fecha;
  final Turno turno;
  final DateTime horaInicioDia;
  final DateTime? horaFinDia;
  final EstadoReporte estado;
  final String? responsableNombre;
  final String? observaciones;

  const ReporteSalidas({
    required this.id,
    required this.fecha,
    required this.turno,
    required this.horaInicioDia,
    this.horaFinDia,
    required this.estado,
    this.responsableNombre,
    this.observaciones,
  });

  factory ReporteSalidas.fromMap(Map<String, dynamic> m) => ReporteSalidas(
        id: (m['id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String),
        turno: Turno.desde(m['turno'] as String),
        horaInicioDia: DateTime.parse(m['hora_inicio_dia'] as String).toLocal(),
        horaFinDia: m['hora_fin_dia'] == null
            ? null
            : DateTime.parse(m['hora_fin_dia'] as String).toLocal(),
        estado: EstadoReporte.desde(m['estado'] as String),
        responsableNombre: m['responsable_nombre'] as String?,
        observaciones: m['observaciones'] as String?,
      );
}

/// Línea del reporte (un sabor/formato), tal como sale de la vista
/// `salidas_reporte_detalle` (ya trae el total calculado).
class LineaSalidas {
  final int id;
  final int reporteId;
  final int saborId;
  final String sabor;
  final int presentacionId;
  final String presentacion;
  final String material;
  final DateTime? horaInicio;
  final DateTime? horaFin;
  final double? petPalets;
  final double? petPaquetesLibres;
  final double? petBotellasLibres;
  final double? vidFilas;
  final double? vidCajasLibres;
  final double? vidBotellasLibres;
  final double? totalBotellas;

  const LineaSalidas({
    required this.id,
    required this.reporteId,
    required this.saborId,
    required this.sabor,
    required this.presentacionId,
    required this.presentacion,
    required this.material,
    this.horaInicio,
    this.horaFin,
    this.petPalets,
    this.petPaquetesLibres,
    this.petBotellasLibres,
    this.vidFilas,
    this.vidCajasLibres,
    this.vidBotellasLibres,
    this.totalBotellas,
  });

  bool get esPet => material == 'pet';

  factory LineaSalidas.fromMap(Map<String, dynamic> m) => LineaSalidas(
        id: (m['id'] as num).toInt(),
        reporteId: (m['reporte_id'] as num).toInt(),
        saborId: (m['sabor_id'] as num).toInt(),
        sabor: m['sabor'] as String,
        presentacionId: (m['presentacion_id'] as num).toInt(),
        presentacion: m['presentacion'] as String,
        material: m['material'] as String,
        horaInicio:
            m['hora_inicio'] == null ? null : DateTime.parse(m['hora_inicio'] as String).toLocal(),
        horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
        petPalets: (m['pet_palets'] as num?)?.toDouble(),
        petPaquetesLibres: (m['pet_paquetes_libres'] as num?)?.toDouble(),
        petBotellasLibres: (m['pet_botellas_libres'] as num?)?.toDouble(),
        vidFilas: (m['vid_filas'] as num?)?.toDouble(),
        vidCajasLibres: (m['vid_cajas_libres'] as num?)?.toDouble(),
        vidBotellasLibres: (m['vid_botellas_libres'] as num?)?.toDouble(),
        totalBotellas: (m['total_botellas'] as num?)?.toDouble(),
      );
}

/// Fila de la Planilla de producción: totales agrupados por sabor/formato.
class PlanillaFila {
  final DateTime fecha;
  final String sabor;
  final String presentacion;
  final String material;
  final int reportes;
  final double? totalBotellas;

  const PlanillaFila({
    required this.fecha,
    required this.sabor,
    required this.presentacion,
    required this.material,
    required this.reportes,
    this.totalBotellas,
  });

  factory PlanillaFila.fromMap(Map<String, dynamic> m) => PlanillaFila(
        fecha: DateTime.parse(m['fecha'] as String),
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String,
        material: m['material'] as String,
        reportes: (m['reportes'] as num).toInt(),
        totalBotellas: (m['total_botellas'] as num?)?.toDouble(),
      );
}

/// Datos para guardar (o actualizar) una línea. [id] no nulo = editar.
class DatosLinea {
  final int? id;
  final int saborId;
  final int presentacionId;
  final DateTime? horaInicio;
  final DateTime? horaFin;
  final double? petPalets;
  final double? petPaquetesLibres;
  final double? petBotellasLibres;
  final double? vidFilas;
  final double? vidCajasLibres;
  final double? vidBotellasLibres;

  const DatosLinea({
    this.id,
    required this.saborId,
    required this.presentacionId,
    this.horaInicio,
    this.horaFin,
    this.petPalets,
    this.petPaquetesLibres,
    this.petBotellasLibres,
    this.vidFilas,
    this.vidCajasLibres,
    this.vidBotellasLibres,
  });
}
