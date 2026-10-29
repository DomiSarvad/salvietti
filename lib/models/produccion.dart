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

/// Un producto embotellado del catálogo (sabor + tamaño + envase, ej.
/// "2,5 L Papaya - Pett"): define qué preforma y qué tapa consume por
/// botella, y de qué fórmula sale el líquido.
class ProductoTerminado {
  final String id;
  final String nombre;
  final String formulaId;
  final String envase; // 'pett' | 'vidrio'
  final double litrosPorBotella;
  final double? botellasPorPaquete;
  final String? preformaId; // null si envase == 'vidrio'
  final String tapaId;
  final String? fotoUrl; // v46: foto pública del producto (bucket "productos")

  ProductoTerminado({
    required this.id,
    required this.nombre,
    required this.formulaId,
    required this.envase,
    required this.litrosPorBotella,
    this.botellasPorPaquete,
    this.preformaId,
    required this.tapaId,
    this.fotoUrl,
  });

  factory ProductoTerminado.fromMap(Map<String, dynamic> m) => ProductoTerminado(
        id: m['id'],
        nombre: m['nombre'],
        formulaId: m['formula_id'],
        envase: m['envase'],
        litrosPorBotella: (m['litros_por_botella'] as num).toDouble(),
        botellasPorPaquete: (m['botellas_por_paquete'] as num?)?.toDouble(),
        preformaId: m['preforma_id'],
        tapaId: m['tapa_id'],
        fotoUrl: m['foto_url'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'formula_id': formulaId,
        'envase': envase,
        'litros_por_botella': litrosPorBotella,
        'botellas_por_paquete': botellasPorPaquete,
        'preforma_id': preformaId,
        'tapa_id': tapaId,
        // Solo si hay foto: así guardar sigue andando aunque no se haya corrido v46.
        if (fotoUrl != null) 'foto_url': fotoUrl,
      };
}

class PlanProduccionDetalle {
  final String id;
  final String planId;
  final String? formulaId;
  final String? productoTerminadoId;
  final String sabor; // denormalizado para mostrar fácil en UI
  final String? nombreProducto; // denormalizado, ej. "2,5 L Papaya - Pett"
  final double? litrosPorBotella; // denormalizado, para estimar botellas
  final double? botellasPorPaquete; // denormalizado, para desglosar paquetes/cajas
  final double litrosPlanificados;
  final double? litrosProducidos;
  final double? botellasProducidas;
  final double mermaLitros;
  final bool completado;

  PlanProduccionDetalle({
    required this.id,
    required this.planId,
    this.formulaId,
    this.productoTerminadoId,
    required this.sabor,
    this.nombreProducto,
    this.litrosPorBotella,
    this.botellasPorPaquete,
    required this.litrosPlanificados,
    this.litrosProducidos,
    this.botellasProducidas,
    this.mermaLitros = 0,
    required this.completado,
  });

  factory PlanProduccionDetalle.fromMap(Map<String, dynamic> m) =>
      PlanProduccionDetalle(
        id: m['id'],
        planId: m['plan_id'],
        formulaId: m['formula_id'],
        productoTerminadoId: m['producto_terminado_id'],
        sabor: m['formulas'] != null ? m['formulas']['sabor'] : (m['sabor'] ?? ''),
        nombreProducto: m['productos_terminados'] != null
            ? m['productos_terminados']['nombre']
            : null,
        litrosPorBotella: m['productos_terminados'] != null
            ? (m['productos_terminados']['litros_por_botella'] as num?)?.toDouble()
            : null,
        botellasPorPaquete: m['productos_terminados'] != null
            ? (m['productos_terminados']['botellas_por_paquete'] as num?)?.toDouble()
            : null,
        litrosPlanificados: (m['litros_planificados'] as num).toDouble(),
        litrosProducidos: (m['litros_producidos'] as num?)?.toDouble(),
        botellasProducidas: (m['botellas_producidas'] as num?)?.toDouble(),
        mermaLitros: (m['merma_litros'] as num?)?.toDouble() ?? 0,
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
