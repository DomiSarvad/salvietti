import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Representa una entrada, salida o ajuste de inventario.
/// Se usa tanto para el registro directo en Supabase como para la cola
/// local (Hive) cuando no hay conexión — de ahí `offlineUuid`, que
/// garantiza idempotencia al sincronizar (evita duplicados).
class Movimiento {
  final String offlineUuid;
  final String tablaOrigen; // 'tapas' | 'preformas' | 'materia_prima'
  final String itemId;
  final String tipo; // 'ingreso' | 'salida' | 'ajuste'
  final double cantidad;
  final String? unidadMedida;
  final String? lote;
  final DateTime? fechaVencimiento;
  final String? proveedor;
  final String? nFactura;
  final String? transportador;
  final double? precioTransporte;
  final String? observacion;
  final String usuarioId;
  final DateTime creadoEn;
  bool sincronizado;

  Movimiento({
    String? offlineUuid,
    required this.tablaOrigen,
    required this.itemId,
    required this.tipo,
    required this.cantidad,
    this.unidadMedida,
    this.lote,
    this.fechaVencimiento,
    this.proveedor,
    this.nFactura,
    this.transportador,
    this.precioTransporte,
    this.observacion,
    required this.usuarioId,
    DateTime? creadoEn,
    this.sincronizado = false,
  })  : offlineUuid = offlineUuid ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  Map<String, dynamic> toSupabaseMap() => {
        'tabla_origen': tablaOrigen,
        'item_id': itemId,
        'tipo': tipo,
        'cantidad': cantidad,
        'unidad_medida': unidadMedida,
        'lote': lote,
        'fecha_vencimiento': fechaVencimiento?.toIso8601String(),
        'proveedor': proveedor,
        'n_factura': nFactura,
        'transportador': transportador,
        'precio_transporte': precioTransporte,
        'observacion': observacion,
        'usuario_id': usuarioId,
        'origen_offline_uuid': offlineUuid,
        'sincronizado': true,
        'created_at': creadoEn.toIso8601String(),
      };

  Map<String, dynamic> toHiveMap() => {
        'offlineUuid': offlineUuid,
        'tablaOrigen': tablaOrigen,
        'itemId': itemId,
        'tipo': tipo,
        'cantidad': cantidad,
        'unidadMedida': unidadMedida,
        'lote': lote,
        'fechaVencimiento': fechaVencimiento?.toIso8601String(),
        'proveedor': proveedor,
        'nFactura': nFactura,
        'transportador': transportador,
        'precioTransporte': precioTransporte,
        'observacion': observacion,
        'usuarioId': usuarioId,
        'creadoEn': creadoEn.toIso8601String(),
        'sincronizado': sincronizado,
      };

  factory Movimiento.fromHiveMap(Map m) => Movimiento(
        offlineUuid: m['offlineUuid'],
        tablaOrigen: m['tablaOrigen'],
        itemId: m['itemId'],
        tipo: m['tipo'],
        cantidad: (m['cantidad'] as num).toDouble(),
        unidadMedida: m['unidadMedida'],
        lote: m['lote'],
        fechaVencimiento: m['fechaVencimiento'] != null
            ? DateTime.tryParse(m['fechaVencimiento'])
            : null,
        proveedor: m['proveedor'],
        nFactura: m['nFactura'],
        transportador: m['transportador'],
        precioTransporte: (m['precioTransporte'] as num?)?.toDouble(),
        observacion: m['observacion'],
        usuarioId: m['usuarioId'],
        creadoEn: DateTime.parse(m['creadoEn']),
        sincronizado: m['sincronizado'] ?? false,
      );
}
