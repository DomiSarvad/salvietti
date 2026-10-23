// Modelos de Pedidos de compra (v43): Almacén pide, el Gerente aprueba.

class ErrorNegocioCompra implements Exception {
  final String mensaje;
  const ErrorNegocioCompra(this.mensaje);
  @override
  String toString() => mensaje;
}

enum EstadoCompra {
  pendiente('pendiente', 'Pendiente'),
  aprobado('aprobado', 'Aprobado'),
  rechazado('rechazado', 'Rechazado'),
  anulado('anulado', 'Anulado');

  final String id;
  final String etiqueta;
  const EstadoCompra(this.id, this.etiqueta);

  static EstadoCompra desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoCompra.pendiente);
}

class LineaCompra {
  final int itemId;
  final String codigo;
  final String detalle;
  final String unidad;
  final double cantidad;
  final String? nota;

  const LineaCompra({
    required this.itemId,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.cantidad,
    this.nota,
  });

  factory LineaCompra.fromMap(Map<String, dynamic> m) {
    final item = (m['inv_items'] as Map?) ?? const {};
    return LineaCompra(
      itemId: (m['item_id'] as num).toInt(),
      codigo: item['codigo'] as String? ?? '',
      detalle: item['detalle'] as String? ?? '',
      unidad: item['unidad'] as String? ?? '',
      cantidad: (m['cantidad'] as num).toDouble(),
      nota: m['nota'] as String?,
    );
  }
}

class PedidoCompra {
  final int id;
  final DateTime fecha;
  final String? motivo;
  final EstadoCompra estado;
  final String solicitanteId;
  final String? solicitanteNombre;
  final String? resueltoPorNombre;
  final DateTime? resueltoEn;
  final String? respuesta;
  final List<LineaCompra> lineas;

  const PedidoCompra({
    required this.id,
    required this.fecha,
    required this.motivo,
    required this.estado,
    required this.solicitanteId,
    required this.solicitanteNombre,
    required this.resueltoPorNombre,
    required this.resueltoEn,
    required this.respuesta,
    required this.lineas,
  });

  factory PedidoCompra.fromMap(Map<String, dynamic> m) => PedidoCompra(
        id: (m['id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String).toLocal(),
        motivo: m['motivo'] as String?,
        estado: EstadoCompra.desde(m['estado'] as String),
        solicitanteId: m['solicitante'] as String,
        solicitanteNombre: m['solicitante_nombre'] as String?,
        resueltoPorNombre: m['resuelto_por_nombre'] as String?,
        resueltoEn: m['resuelto_en'] == null
            ? null
            : DateTime.parse(m['resuelto_en'] as String).toLocal(),
        respuesta: m['respuesta'] as String?,
        lineas: [
          for (final l in (m['compras_pedido_lineas'] as List? ?? const []))
            LineaCompra.fromMap(Map<String, dynamic>.from(l as Map))
        ],
      );
}

/// Un ítem del catálogo para elegir al armar el pedido.
class ItemCompra {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  const ItemCompra({required this.id, required this.codigo, required this.detalle, required this.unidad});

  factory ItemCompra.fromMap(Map<String, dynamic> m) => ItemCompra(
        id: (m['id'] as num).toInt(),
        codigo: m['codigo'] as String? ?? '',
        detalle: m['detalle'] as String? ?? '',
        unidad: m['unidad'] as String? ?? '',
      );
}

/// Una línea del formulario "Nuevo pedido de compra".
class LineaNueva {
  final ItemCompra item;
  final double cantidad;
  final String? nota;
  const LineaNueva({required this.item, required this.cantidad, this.nota});
}
