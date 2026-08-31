class Insumo {
  final String id;
  final String tabla; // 'tapas' | 'preformas' | 'materia_prima'
  final String codigo;
  final String detalle;
  final String? formato;
  final String? color;
  final String? tamano;
  final String unidadMedida;
  final double cantidadSistema;
  final double cantidadReal;
  final double? cantidadCajas;
  final double? unidadesPorCaja;
  final String? tipoEnvase;
  final double? cantidadPorEnvase;
  final String? proveedorHabitual;
  final double consumoPromedioDia;
  final double stockMinimo;
  final bool activo;
  final DateTime? updatedAt;
  final String? area; // solo materia_prima: null = general, 'jarabes' = su área

  Insumo({
    required this.id,
    required this.tabla,
    required this.codigo,
    required this.detalle,
    this.formato,
    this.color,
    this.tamano,
    required this.unidadMedida,
    required this.cantidadSistema,
    required this.cantidadReal,
    this.cantidadCajas,
    this.unidadesPorCaja,
    this.tipoEnvase,
    this.cantidadPorEnvase,
    this.proveedorHabitual,
    this.consumoPromedioDia = 0,
    this.stockMinimo = 0,
    this.activo = true,
    this.updatedAt,
    this.area,
  });

  /// Días estimados de existencia = stock actual / consumo promedio diario.
  /// Si no hay consumo registrado, se considera indefinido (999 = sin riesgo).
  double get diasExistencia =>
      consumoPromedioDia > 0 ? cantidadReal / consumoPromedioDia : 999;

  factory Insumo.fromMap(Map<String, dynamic> m, String tabla) {
    return Insumo(
      id: m['id'] as String,
      tabla: tabla,
      codigo: m['codigo'] ?? '',
      detalle: m['detalle'] ?? '',
      formato: m['formato'],
      color: m['color'],
      tamano: m['tamano'],
      unidadMedida: m['unidad_medida'] ?? '',
      cantidadSistema: (m['cantidad_sistema'] as num?)?.toDouble() ?? 0,
      cantidadReal: (m['cantidad_real'] as num?)?.toDouble() ?? 0,
      cantidadCajas: (m['cantidad_cajas'] as num?)?.toDouble(),
      unidadesPorCaja: (m['unidades_por_caja'] as num?)?.toDouble(),
      tipoEnvase: m['tipo_envase'],
      cantidadPorEnvase: (m['cantidad_por_envase'] as num?)?.toDouble(),
      proveedorHabitual: m['proveedor_habitual'],
      consumoPromedioDia: (m['consumo_promedio_dia'] as num?)?.toDouble() ?? 0,
      stockMinimo: (m['stock_minimo'] as num?)?.toDouble() ?? 0,
      activo: m['activo'] ?? true,
      updatedAt:
          m['updated_at'] != null ? DateTime.tryParse(m['updated_at']) : null,
      area: m['area'],
    );
  }

  Map<String, dynamic> toMap() {
    // Declaramos explícitamente el mapa como <String, dynamic> para permitir valores nulos
    final Map<String, dynamic> base = {
      'detalle': detalle,
      'unidad_medida': unidadMedida,
      'cantidad_sistema': cantidadSistema,
      'cantidad_real': cantidadReal,
      'stock_minimo': stockMinimo,
    };

    if (tabla == 'tapas') {
      base.addAll(<String, dynamic>{
        'formato': formato,
        'color': color,
        'cantidad_cajas': cantidadCajas,
        'unidades_por_caja': unidadesPorCaja,
      });
    } else if (tabla == 'preformas') {
      base.addAll(<String, dynamic>{
        'formato': formato,
        'tamano': tamano,
        'cantidad_cajas': cantidadCajas,
        'unidades_por_caja': unidadesPorCaja,
      });
    } else if (tabla == 'materia_prima') {
      base.addAll(<String, dynamic>{
        'tipo_envase': tipoEnvase,
        'cantidad_por_envase': cantidadPorEnvase,
        'proveedor_habitual': proveedorHabitual,
        'area': area,
      });
    }
    return base;
  }
}
