// Modelos del módulo de pedidos internos, entregas y conformidad.

/// Error de negocio con un mensaje listo para mostrar (lo lanzan las
/// funciones del servidor con `raise exception`).
class ErrorNegocio implements Exception {
  final String mensaje;
  const ErrorNegocio(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Áreas que reciben materiales (coinciden con `area_de_rol` del servidor).
class AreaPedido {
  static const etiquetas = {
    'jarabes': 'Jarabes',
    'soplado': 'Soplado',
    'llenadora': 'Llenadora',
    'codificacion': 'Codificación',
    'calidad': 'Control de Calidad',
    'soda_caustica': 'Soda cáustica',
    'salidas': 'Registro de salidas',
  };

  static const todas = ['jarabes', 'soplado', 'llenadora', 'codificacion', 'calidad', 'soda_caustica', 'salidas'];

  static String etiqueta(String id) => etiquetas[id] ?? id;

  /// Área a la que pertenece un rol (null si no recibe materiales).
  static String? deRol(String rol) {
    switch (rol) {
      case 'jarabes':
      case 'ayudante_jarabes':
        return 'jarabes';
      case 'soplado':
        return 'soplado';
      case 'llenadora':
        return 'llenadora';
      case 'codificacion':
        return 'codificacion';
      case 'control_calidad':
        return 'calidad';
      case 'soda_caustica':
        return 'soda_caustica';
      case 'registro_salidas':
        return 'salidas';
      default:
        return null;
    }
  }
}

enum EstadoPedido {
  pendiente('pendiente', 'Por entregar'),
  entregado('entregado', 'Por confirmar'),
  observado('observado', 'Con observaciones'),
  cerrado('cerrado', 'Cerrado'),
  anulado('anulado', 'Anulado');

  final String id;
  final String etiqueta;
  const EstadoPedido(this.id, this.etiqueta);

  static EstadoPedido desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoPedido.pendiente);
}

class LoteEntregado {
  final String? nLote;
  final DateTime? vencimiento;
  final double cantidad;
  const LoteEntregado({this.nLote, this.vencimiento, required this.cantidad});

  factory LoteEntregado.fromMap(Map<String, dynamic> m) => LoteEntregado(
        nLote: m['n_lote'] as String?,
        vencimiento: m['fecha_vencimiento'] == null
            ? null
            : DateTime.parse(m['fecha_vencimiento'] as String),
        cantidad: (m['cantidad'] as num).toDouble(),
      );
}

class LineaPedido {
  final int id;
  final int itemId;
  final String codigo;
  final String detalle;
  final String unidad;
  final double cantidadPedida;
  final double? cantidadEntregada;
  final double? cantidadRecibida;
  final bool? recibidoOk;
  final String? observacion;
  final List<LoteEntregado> lotes;
  final double cantidadDevuelta;

  const LineaPedido({
    required this.id,
    required this.itemId,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.cantidadPedida,
    this.cantidadEntregada,
    this.cantidadRecibida,
    this.recibidoOk,
    this.observacion,
    this.lotes = const [],
    this.cantidadDevuelta = 0,
  });

  /// Lo entregado que todavía no se devolvió (lo que sobró de esta línea).
  double get disponibleParaDevolver => (cantidadEntregada ?? 0) - cantidadDevuelta;

  factory LineaPedido.fromMap(Map<String, dynamic> m) {
    final item = Map<String, dynamic>.from(m['inv_items'] as Map);
    final lotes = (m['inv_entrega_lotes'] as List?) ?? const [];
    final devoluciones = (m['inv_devoluciones'] as List?) ?? const [];
    return LineaPedido(
      id: (m['id'] as num).toInt(),
      itemId: (m['item_id'] as num).toInt(),
      codigo: (item['codigo'] as String?) ?? '',
      detalle: item['detalle'] as String,
      unidad: item['unidad'] as String,
      cantidadPedida: (m['cantidad_pedida'] as num).toDouble(),
      cantidadEntregada: (m['cantidad_entregada'] as num?)?.toDouble(),
      cantidadRecibida: (m['cantidad_recibida'] as num?)?.toDouble(),
      recibidoOk: m['recibido_ok'] as bool?,
      observacion: m['observacion'] as String?,
      lotes: [
        for (final l in lotes) LoteEntregado.fromMap(Map<String, dynamic>.from(l as Map))
      ],
      cantidadDevuelta: devoluciones.fold<double>(
          0, (s, d) => s + ((Map<String, dynamic>.from(d as Map)['cantidad'] as num).toDouble())),
    );
  }
}

class Pedido {
  final int id;
  final DateTime fecha;
  final String areaDestino;
  final String almacenOrigen;
  final String? almacenDestino;
  final String? motivo;
  final EstadoPedido estado;
  final String solicitanteId;
  final String? solicitanteNombre;
  final String? entregadoPorNombre;
  final DateTime? entregadoEn;
  final String? confirmadoPorNombre;
  final DateTime? confirmadoEn;
  final String? notaConformidad;
  final String? resolucion;
  final List<LineaPedido> lineas;

  const Pedido({
    required this.id,
    required this.fecha,
    required this.areaDestino,
    required this.almacenOrigen,
    this.almacenDestino,
    this.motivo,
    required this.estado,
    required this.solicitanteId,
    this.solicitanteNombre,
    this.entregadoPorNombre,
    this.entregadoEn,
    this.confirmadoPorNombre,
    this.confirmadoEn,
    this.notaConformidad,
    this.resolucion,
    this.lineas = const [],
  });

  static DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  factory Pedido.fromMap(Map<String, dynamic> m) {
    final lineas = (m['inv_pedido_lineas'] as List?) ?? const [];
    return Pedido(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String),
      areaDestino: m['area_destino'] as String,
      almacenOrigen: m['almacen_origen'] as String,
      almacenDestino: m['almacen_destino'] as String?,
      motivo: m['motivo'] as String?,
      estado: EstadoPedido.desde(m['estado'] as String),
      solicitanteId: m['solicitante'] as String,
      solicitanteNombre: m['solicitante_nombre'] as String?,
      entregadoPorNombre: m['entregado_por_nombre'] as String?,
      entregadoEn: _ts(m['entregado_en']),
      confirmadoPorNombre: m['confirmado_por_nombre'] as String?,
      confirmadoEn: _ts(m['confirmado_en']),
      notaConformidad: m['nota_conformidad'] as String?,
      resolucion: m['resolucion'] as String?,
      lineas: [
        for (final l in lineas) LineaPedido.fromMap(Map<String, dynamic>.from(l as Map))
      ]..sort((a, b) => a.id.compareTo(b.id)),
    );
  }
}

/// Ítem que se puede pedir, con lo que hay en el almacén de origen.
class ItemPedible {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  final double disponible;
  const ItemPedible({
    required this.id,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.disponible,
  });

  factory ItemPedible.fromMap(Map<String, dynamic> m) => ItemPedible(
        id: (m['item_id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        disponible: (m['cantidad_sistema'] as num?)?.toDouble() ?? 0,
      );
}

class LineaNueva {
  final int itemId;
  final double cantidad;
  const LineaNueva({required this.itemId, required this.cantidad});
  Map<String, dynamic> toMap() => {'item_id': itemId, 'cantidad': cantidad};
}

class ConfirmacionLinea {
  final int lineaId;
  final bool recibidoOk;
  final double cantidadRecibida;
  final String? observacion;
  const ConfirmacionLinea({
    required this.lineaId,
    required this.recibidoOk,
    required this.cantidadRecibida,
    this.observacion,
  });
  Map<String, dynamic> toMap() => {
        'linea_id': lineaId,
        'recibido_ok': recibidoOk,
        'cantidad_recibida': cantidadRecibida,
        'observacion': observacion,
      };
}
