/// Una fila de la vista `inv_movimientos_detalle`: un movimiento de stock de
/// un ítem en un almacén (recepción, entrega, conteo, manual…).
class MovimientoInv {
  final int id;
  final DateTime fecha;
  final int itemId;
  final String almacenId;
  final String tipo; // entrada | salida | ajuste | transferencia
  final double cantidad; // con signo: entrada +, salida −
  final String? referenciaTipo;
  final int? referenciaId;
  final String? motivo;
  final String? usuarioNombre;
  final String? nLote;
  final DateTime? fechaVencimiento;
  final bool revertido;

  const MovimientoInv({
    required this.id,
    required this.fecha,
    required this.itemId,
    required this.almacenId,
    required this.tipo,
    required this.cantidad,
    this.referenciaTipo,
    this.referenciaId,
    this.motivo,
    this.usuarioNombre,
    this.nLote,
    this.fechaVencimiento,
    this.revertido = false,
  });

  factory MovimientoInv.fromMap(Map<String, dynamic> m) => MovimientoInv(
        id: (m['id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String).toLocal(),
        itemId: (m['item_id'] as num).toInt(),
        almacenId: m['almacen_id'] as String,
        tipo: m['tipo'] as String,
        cantidad: (m['cantidad'] as num).toDouble(),
        referenciaTipo: m['referencia_tipo'] as String?,
        referenciaId: (m['referencia_id'] as num?)?.toInt(),
        motivo: m['motivo'] as String?,
        usuarioNombre: m['usuario_nombre'] as String?,
        nLote: m['n_lote'] as String?,
        fechaVencimiento: m['fecha_vencimiento'] == null
            ? null
            : DateTime.parse(m['fecha_vencimiento'] as String),
        revertido: (m['revertido'] as bool?) ?? false,
      );

  /// Solo los movimientos manuales se pueden revertir desde acá; el resto
  /// (recepción, entrega, conteo) se corrige en su propio módulo.
  bool get esManual => referenciaTipo == 'manual';
  bool get sePuedeRevertir => esManual && !revertido;

  /// De dónde viene el movimiento, en palabras del almacén.
  String get origen {
    switch (referenciaTipo) {
      case 'recepcion':
        return 'Recepción';
      case 'entrega':
        return 'Entrega';
      case 'conteo':
        return 'Conteo físico';
      case 'manual':
        return 'Manual';
      case 'reversion':
        return 'Reversión';
      case 'soplado_corrida':
        return 'Soplado';
      default:
        return referenciaTipo == null ? 'Saldo' : referenciaTipo!;
    }
  }
}
