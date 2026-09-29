import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Representa una entrada, salida o ajuste de inventario.
/// Se usa tanto para el registro directo en Supabase como para la cola
/// local (Hive) cuando no hay conexión — de ahí `offlineUuid`, que
/// garantiza idempotencia al sincronizar (evita duplicados).
class Movimiento {
  final String? id; // id real en Supabase (null si todavía no se insertó)
  final String offlineUuid;
  final String tablaOrigen; // 'tapas' | 'preformas' | 'materia_prima'
  final String itemId;
  final String tipo; // 'ingreso' | 'salida' | 'ajuste' | 'produccion'
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
  final String? revierteMovimientoId; // si esta fila deshace a otra
  /// 'manual' o 'importacion_excel' (cargado desde un Excel).
  final String origen;
  /// Movimiento de historial que NO modifica el stock (importaciones cuyo
  /// stock ya estaba cargado).
  final bool soloHistorial;
  final String? importacionId; // agrupa las filas de una misma importación
  bool sincronizado;

  Movimiento({
    this.id,
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
    this.revierteMovimientoId,
    this.origen = 'manual',
    this.soloHistorial = false,
    this.importacionId,
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
        if (revierteMovimientoId != null)
          'revierte_movimiento_id': revierteMovimientoId,
        // Solo se envían si es una importación: así los movimientos manuales
        // siguen funcionando aunque la migración v13 no esté aplicada.
        if (origen != 'manual') ...{
          'origen': origen,
          'solo_historial': soloHistorial,
          'importacion_id': importacionId,
        },
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

  /// Para leer movimientos ya guardados en Supabase (historial/reportes).
  factory Movimiento.fromMap(Map<String, dynamic> m) => Movimiento(
        id: m['id'],
        offlineUuid: m['origen_offline_uuid'] ?? m['id'],
        tablaOrigen: m['tabla_origen'],
        itemId: m['item_id'],
        tipo: m['tipo'],
        cantidad: (m['cantidad'] as num).toDouble(),
        unidadMedida: m['unidad_medida'],
        lote: m['lote'],
        fechaVencimiento: m['fecha_vencimiento'] != null
            ? DateTime.tryParse(m['fecha_vencimiento'])
            : null,
        proveedor: m['proveedor'],
        nFactura: m['n_factura'],
        transportador: m['transportador'],
        precioTransporte: (m['precio_transporte'] as num?)?.toDouble(),
        observacion: m['observacion'],
        usuarioId: m['usuario_id'] ?? '',
        creadoEn: DateTime.parse(m['created_at']),
        revierteMovimientoId: m['revierte_movimiento_id'],
        origen: m['origen'] ?? 'manual',
        soloHistorial: m['solo_historial'] ?? false,
        importacionId: m['importacion_id'],
        sincronizado: true,
      );

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
