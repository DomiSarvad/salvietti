// Modelos propios del Inicio. El stock por ítem reutiliza `ExistenciaItem`
// de Inventario (mismo dato, sin duplicar el modelo).

/// Un movimiento reciente, con el nombre del ítem ya resuelto (para el
/// listado global del Inicio, a diferencia de `MovimientoInv` que es por
/// ítem dentro de un almacén).
class MovimientoReciente {
  final int id;
  final DateTime fecha;
  final String almacenId;
  final String itemDetalle;
  final String itemCodigo;
  final String unidad;
  final String tipo; // entrada | salida | ajuste | transferencia
  final double cantidad;
  final String? motivo;

  const MovimientoReciente({
    required this.id,
    required this.fecha,
    required this.almacenId,
    required this.itemDetalle,
    required this.itemCodigo,
    required this.unidad,
    required this.tipo,
    required this.cantidad,
    this.motivo,
  });

  factory MovimientoReciente.fromMap(Map<String, dynamic> m) {
    final item = Map<String, dynamic>.from(m['inv_items'] as Map);
    return MovimientoReciente(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String).toLocal(),
      almacenId: m['almacen_id'] as String,
      itemDetalle: item['detalle'] as String,
      itemCodigo: (item['codigo'] as String?) ?? '',
      unidad: item['unidad'] as String,
      tipo: m['tipo'] as String,
      cantidad: (m['cantidad'] as num).toDouble(),
      motivo: m['motivo'] as String?,
    );
  }
}
