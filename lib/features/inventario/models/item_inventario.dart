/// Ítem del catálogo (tabla `inv_items`): lo que se da de alta o se edita.
class ItemInventario {
  final int? id;
  final String? codigo; // lo genera el servidor (IN-0001 / MP-0001)
  final int categoriaId;
  final String detalle;
  final String unidad;
  final String? unidadCompra; // quintal, bidón, bolsa, caja…
  final double? factorCompra; // cuántas "unidad" trae cada envase (ej. 46 kg)
  final int? unidadesPorCaja;
  final double? stockMinimo;
  final double? consumoDiarioManual;

  /// color, formato, peso_g, ancho_mm, micronaje… (solo los que se llenan).
  final Map<String, dynamic> atributos;

  const ItemInventario({
    this.id,
    this.codigo,
    required this.categoriaId,
    required this.detalle,
    required this.unidad,
    this.unidadCompra,
    this.factorCompra,
    this.unidadesPorCaja,
    this.stockMinimo,
    this.consumoDiarioManual,
    this.atributos = const {},
  });

  factory ItemInventario.fromMap(Map<String, dynamic> m) => ItemInventario(
        id: (m['id'] as num).toInt(),
        codigo: m['codigo'] as String?,
        categoriaId: (m['categoria_id'] as num).toInt(),
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        unidadCompra: m['unidad_compra'] as String?,
        factorCompra: (m['factor_compra'] as num?)?.toDouble(),
        unidadesPorCaja: (m['unidades_por_caja'] as num?)?.toInt(),
        stockMinimo: (m['stock_minimo'] as num?)?.toDouble(),
        consumoDiarioManual: (m['consumo_diario_manual'] as num?)?.toDouble(),
        atributos: Map<String, dynamic>.from((m['atributos'] as Map?) ?? const {}),
      );

  Map<String, dynamic> toMap() => {
        'categoria_id': categoriaId,
        'detalle': detalle,
        'unidad': unidad,
        'unidad_compra': unidadCompra,
        'factor_compra': factorCompra,
        'unidades_por_caja': unidadesPorCaja,
        'stock_minimo': stockMinimo,
        'consumo_diario_manual': consumoDiarioManual,
        'atributos': atributos,
      };
}
