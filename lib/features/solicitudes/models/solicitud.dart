// Modelos del módulo de Solicitudes a Gerencia.

class ErrorNegocioSolicitud implements Exception {
  final String mensaje;
  const ErrorNegocioSolicitud(this.mensaje);
  @override
  String toString() => mensaje;
}

class TipoSolicitud {
  static const suministro = 'suministro';
  static const autorizacion = 'autorizacion';
  static const cambioReceta = 'cambio_receta';
  static const otro = 'otro';

  static const todos = [suministro, autorizacion, cambioReceta, otro];

  static String etiqueta(String id) {
    switch (id) {
      case suministro:
        return 'Falta de suministro';
      case autorizacion:
        return 'Autorización';
      case cambioReceta:
        return 'Cambio de receta';
      default:
        return 'Otro';
    }
  }
}

enum EstadoSolicitud {
  pendiente('pendiente', 'Pendiente'),
  aprobada('aprobada', 'Aprobada'),
  rechazada('rechazada', 'Rechazada');

  final String id;
  final String etiqueta;
  const EstadoSolicitud(this.id, this.etiqueta);

  static EstadoSolicitud desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoSolicitud.pendiente);
}

class Solicitud {
  final int id;
  final DateTime fecha;
  final String tipo;
  final String asunto;
  final String? detalle;
  final int? itemId;
  final String? itemDetalle;
  final String? itemUnidad;
  final double? cantidadSugerida;
  final EstadoSolicitud estado;
  final String solicitanteId;
  final String? solicitanteNombre;
  final String? solicitanteRol;
  final String? resueltaPorNombre;
  final DateTime? resueltaEn;
  final String? respuesta;

  const Solicitud({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.asunto,
    this.detalle,
    this.itemId,
    this.itemDetalle,
    this.itemUnidad,
    this.cantidadSugerida,
    required this.estado,
    required this.solicitanteId,
    this.solicitanteNombre,
    this.solicitanteRol,
    this.resueltaPorNombre,
    this.resueltaEn,
    this.respuesta,
  });

  factory Solicitud.fromMap(Map<String, dynamic> m) {
    final item = m['inv_items'] as Map?;
    return Solicitud(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String).toLocal(),
      tipo: m['tipo'] as String,
      asunto: m['asunto'] as String,
      detalle: m['detalle'] as String?,
      itemId: (m['item_id'] as num?)?.toInt(),
      itemDetalle: item?['detalle'] as String?,
      itemUnidad: item?['unidad'] as String?,
      cantidadSugerida: (m['cantidad_sugerida'] as num?)?.toDouble(),
      estado: EstadoSolicitud.desde(m['estado'] as String),
      solicitanteId: m['solicitante'] as String,
      solicitanteNombre: m['solicitante_nombre'] as String?,
      solicitanteRol: m['solicitante_rol'] as String?,
      resueltaPorNombre: m['resuelta_por_nombre'] as String?,
      resueltaEn:
          m['resuelta_en'] == null ? null : DateTime.parse(m['resuelta_en'] as String).toLocal(),
      respuesta: m['respuesta'] as String?,
    );
  }
}

/// Ítem de referencia para "falta este insumo" (catálogo liviano).
class ItemReferencia {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  const ItemReferencia(
      {required this.id, required this.codigo, required this.detalle, required this.unidad});

  factory ItemReferencia.fromMap(Map<String, dynamic> m) => ItemReferencia(
        id: (m['id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
      );
}

class SolicitudNueva {
  final String tipo;
  final String asunto;
  final String? detalle;
  final int? itemId;
  final double? cantidadSugerida;
  const SolicitudNueva({
    required this.tipo,
    required this.asunto,
    this.detalle,
    this.itemId,
    this.cantidadSugerida,
  });
}
