// Modelos del módulo de Soda Cáustica.

class ErrorNegocioSoda implements Exception {
  final String mensaje;
  const ErrorNegocioSoda(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Ítem del catálogo (la Soda Cáustica vive en Almacén General › Saneamiento,
/// pero el buscador no se restringe: puede haber más de un producto).
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

class EntregaSoda {
  final int id;
  final DateTime fechaHora;
  final int itemId;
  final String codigo;
  final String detalle;
  final String unidad;
  final double cantidad;
  final String entregadoA;
  final String? areaRecibe;
  final String? motivo;
  final double? saldoRestante;
  final String? responsableNombre;

  const EntregaSoda({
    required this.id,
    required this.fechaHora,
    required this.itemId,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.cantidad,
    required this.entregadoA,
    this.areaRecibe,
    this.motivo,
    this.saldoRestante,
    this.responsableNombre,
  });

  factory EntregaSoda.fromMap(Map<String, dynamic> m) => EntregaSoda(
        id: (m['id'] as num).toInt(),
        fechaHora: DateTime.parse(m['fecha_hora'] as String).toLocal(),
        itemId: (m['item_id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        cantidad: (m['cantidad'] as num).toDouble(),
        entregadoA: m['entregado_a'] as String,
        areaRecibe: m['area_recibe'] as String?,
        motivo: m['motivo'] as String?,
        saldoRestante: (m['saldo_restante'] as num?)?.toDouble(),
        responsableNombre: m['responsable_nombre'] as String?,
      );
}
