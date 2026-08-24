class Formula {
  final String id;
  final String sabor;
  final double rendimientoLitros;

  Formula({required this.id, required this.sabor, required this.rendimientoLitros});

  factory Formula.fromMap(Map<String, dynamic> m) => Formula(
        id: m['id'],
        sabor: m['sabor'],
        rendimientoLitros: (m['rendimiento_litros'] as num).toDouble(),
      );
}

class PlanProduccionDetalle {
  final String id;
  final String planId;
  final String formulaId;
  final String sabor; // denormalizado para mostrar fácil en UI
  final double litrosPlanificados;
  final bool completado;

  PlanProduccionDetalle({
    required this.id,
    required this.planId,
    required this.formulaId,
    required this.sabor,
    required this.litrosPlanificados,
    required this.completado,
  });

  factory PlanProduccionDetalle.fromMap(Map<String, dynamic> m) =>
      PlanProduccionDetalle(
        id: m['id'],
        planId: m['plan_id'],
        formulaId: m['formula_id'],
        sabor: m['formulas'] != null ? m['formulas']['sabor'] : (m['sabor'] ?? ''),
        litrosPlanificados: (m['litros_planificados'] as num).toDouble(),
        completado: m['completado'] ?? false,
      );
}

class PlanProduccion {
  final String id;
  final DateTime fecha;
  final String estado;
  final List<PlanProduccionDetalle> detalle;

  PlanProduccion({
    required this.id,
    required this.fecha,
    required this.estado,
    this.detalle = const [],
  });

  factory PlanProduccion.fromMap(Map<String, dynamic> m) => PlanProduccion(
        id: m['id'],
        fecha: DateTime.parse(m['fecha']),
        estado: m['estado'],
        detalle: (m['plan_produccion_detalle'] as List? ?? [])
            .map((d) => PlanProduccionDetalle.fromMap(d))
            .toList(),
      );
}
