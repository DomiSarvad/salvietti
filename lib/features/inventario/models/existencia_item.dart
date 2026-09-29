/// Fila de la vista `inv_existencia`: un ítem con su stock en un almacén.
class ExistenciaItem {
  final int itemId;
  final String codigo;
  final String detalle;
  final String unidad;
  final int categoriaId;
  final String almacenId;
  final double cantidadSistema;
  final double? cantidadReal; // último conteo físico
  final double? consumoDiario;
  final double? diasExistencia;
  final double? stockMinimo;

  const ExistenciaItem({
    required this.itemId,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.categoriaId,
    required this.almacenId,
    required this.cantidadSistema,
    this.cantidadReal,
    this.consumoDiario,
    this.diasExistencia,
    this.stockMinimo,
  });

  factory ExistenciaItem.fromMap(Map<String, dynamic> m) => ExistenciaItem(
        itemId: (m['item_id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        categoriaId: (m['categoria_id'] as num).toInt(),
        almacenId: m['almacen_id'] as String,
        cantidadSistema: (m['cantidad_sistema'] as num?)?.toDouble() ?? 0,
        cantidadReal: (m['cantidad_real'] as num?)?.toDouble(),
        consumoDiario: (m['consumo_diario'] as num?)?.toDouble(),
        diasExistencia: (m['dias_existencia'] as num?)?.toDouble(),
        stockMinimo: (m['stock_minimo'] as num?)?.toDouble(),
      );

  /// Diferencia entre el último conteo físico y el sistema (null si nunca se contó).
  double? get diferencia =>
      cantidadReal == null ? null : cantidadReal! - cantidadSistema;
}
