// Modelos del módulo de Recepciones.
import 'dart:typed_data';


class AlmacenRec {
  final String id;
  final String nombre;
  const AlmacenRec({required this.id, required this.nombre});

  factory AlmacenRec.fromMap(Map<String, dynamic> m) =>
      AlmacenRec(id: m['id'] as String, nombre: m['nombre'] as String);
}

class Proveedor {
  final int id;
  final String nombre;
  const Proveedor({required this.id, required this.nombre});

  factory Proveedor.fromMap(Map<String, dynamic> m) =>
      Proveedor(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

/// Ítem que se puede recibir en un almacén.
class ItemRecepcion {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  final String almacenId;
  const ItemRecepcion({
    required this.id,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    required this.almacenId,
  });

  factory ItemRecepcion.fromMap(Map<String, dynamic> m) => ItemRecepcion(
        id: (m['id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        almacenId: (m['inv_categorias'] as Map)['almacen_id'] as String,
      );
}

/// Recepción ya guardada (vista `inv_recepciones_detalle`).
class RecepcionDetalle {
  final int id;
  final DateTime fecha;
  final String almacenId;
  final int itemId;
  final String codigo;
  final String detalle;
  final String unidad;
  final String? proveedor;
  final String? nFactura;
  final double cantidadFactura;
  final double cantidadReal;
  final double diferencia; // real − factura: negativa = faltó
  final String? nLote;
  final DateTime? fechaFabricacion;
  final DateTime? fechaVencimiento;
  final String? senasac;
  final String? transportador;
  final double? precioTransporte;
  final String? fotoUrl; // ruta dentro del bucket privado (la única, hasta v46)
  final List<String> fotosExtra; // v46: todas las rutas
  final String? observaciones;

  /// Todas las fotos (las de antes de v46 tienen solo [fotoUrl]).
  List<String> get fotos => {if (fotoUrl != null) fotoUrl!, ...fotosExtra}.toList();

  const RecepcionDetalle({
    required this.id,
    required this.fecha,
    required this.almacenId,
    required this.itemId,
    required this.codigo,
    required this.detalle,
    required this.unidad,
    this.proveedor,
    this.nFactura,
    required this.cantidadFactura,
    required this.cantidadReal,
    required this.diferencia,
    this.nLote,
    this.fechaFabricacion,
    this.fechaVencimiento,
    this.senasac,
    this.transportador,
    this.precioTransporte,
    this.fotoUrl,
    this.fotosExtra = const [],
    this.observaciones,
  });

  static DateTime? _fecha(Object? v) => v == null ? null : DateTime.parse(v as String);

  factory RecepcionDetalle.fromMap(Map<String, dynamic> m) => RecepcionDetalle(
        id: (m['id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String),
        almacenId: m['almacen_id'] as String,
        itemId: (m['item_id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        proveedor: m['proveedor'] as String?,
        nFactura: m['n_factura'] as String?,
        cantidadFactura: (m['cantidad_factura'] as num).toDouble(),
        cantidadReal: (m['cantidad_real'] as num).toDouble(),
        diferencia: (m['diferencia'] as num).toDouble(),
        nLote: m['n_lote'] as String?,
        fechaFabricacion: _fecha(m['fecha_fabricacion']),
        fechaVencimiento: _fecha(m['fecha_vencimiento']),
        senasac: m['senasac'] as String?,
        transportador: m['transportador'] as String?,
        precioTransporte: (m['precio_transporte'] as num?)?.toDouble(),
        fotoUrl: m['foto_url'] as String?,
        fotosExtra: [for (final f in (m['fotos'] as List?) ?? const []) f as String],
        observaciones: m['observaciones'] as String?,
      );
}

/// Datos de una recepción nueva, ya en la unidad del ítem.
class RecepcionNueva {
  final String almacenId;
  final int itemId;
  final int? proveedorId;
  final DateTime fecha;
  final String? nFactura;
  final double cantidadFactura;
  final double cantidadReal;
  final String? nLote;
  final DateTime? fechaFabricacion;
  final DateTime? fechaVencimiento;
  final String? senasac;
  final String? transportador;
  final double? precioTransporte;
  final List<String> fotos;
  final String? observaciones;

  const RecepcionNueva({
    required this.almacenId,
    required this.itemId,
    this.proveedorId,
    required this.fecha,
    this.nFactura,
    required this.cantidadFactura,
    required this.cantidadReal,
    this.nLote,
    this.fechaFabricacion,
    this.fechaVencimiento,
    this.senasac,
    this.transportador,
    this.precioTransporte,
    this.fotos = const [],
    this.observaciones,
  });

  static String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

  Map<String, dynamic> toMap() => {
        'almacen_id': almacenId,
        'item_id': itemId,
        'proveedor_id': proveedorId,
        'fecha': _dia(fecha),
        'n_factura': nFactura,
        'cantidad_factura': cantidadFactura,
        'cantidad_real': cantidadReal,
        'n_lote': nLote,
        'fecha_fabricacion': fechaFabricacion == null ? null : _dia(fechaFabricacion!),
        'fecha_vencimiento': fechaVencimiento == null ? null : _dia(fechaVencimiento!),
        'senasac': senasac,
        'transportador': transportador,
        'precio_transporte': precioTransporte,
        'foto_url': fotos.isEmpty ? null : fotos.first,
        // Solo con más de una: así una recepción con una foto se guarda aunque
        // todavía no se haya corrido v46.
        if (fotos.length > 1) 'fotos': fotos,
        'observaciones': observaciones,
      };
}

/// Fila de la vista `inv_diferencias_mes`: lo acumulado del mes por
/// proveedor e ítem, para hacer el reclamo.
class DiferenciaMes {
  final DateTime mes;
  final String detalle;
  final String unidad;
  final String? proveedor;
  final int recepciones;
  final double cantidadFactura;
  final double diferencia;
  final double? porcentaje;

  const DiferenciaMes({
    required this.mes,
    required this.detalle,
    required this.unidad,
    this.proveedor,
    required this.recepciones,
    required this.cantidadFactura,
    required this.diferencia,
    this.porcentaje,
  });

  factory DiferenciaMes.fromMap(Map<String, dynamic> m) => DiferenciaMes(
        mes: DateTime.parse(m['mes'] as String),
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        proveedor: m['proveedor'] as String?,
        recepciones: (m['recepciones'] as num).toInt(),
        cantidadFactura: (m['cantidad_factura'] as num).toDouble(),
        diferencia: (m['diferencia'] as num).toDouble(),
        porcentaje: (m['porcentaje'] as num?)?.toDouble(),
      );
}

/// Foto adjunta (factura o etiqueta de la caja) todavía sin subir.
class FotoAdjunta {
  final Uint8List bytes;
  final String nombre;
  const FotoAdjunta({required this.bytes, required this.nombre});

  String get extension {
    final i = nombre.lastIndexOf('.');
    return i < 0 ? '' : nombre.substring(i + 1).toLowerCase();
  }
}

/// Lo que se escribe en el formulario, antes de validar y convertir.
class BorradorRecepcion {
  final String almacenId;
  final ItemRecepcion? item;
  final Proveedor? proveedor;
  final DateTime fecha;

  /// Unidad en la que se escribieron las cantidades (puede ser GR para un
  /// ítem que se controla en KG; el service la convierte).
  final String unidadEntrada;
  final double? cantidadFactura;
  final double? cantidadReal;
  final String nFactura;
  final String nLote;
  final DateTime? fechaFabricacion;
  final DateTime? fechaVencimiento;
  final String senasac;
  final String transportador;
  final double? precioTransporte;
  final String observaciones;
  final List<FotoAdjunta> fotos;

  const BorradorRecepcion({
    required this.almacenId,
    required this.item,
    this.proveedor,
    required this.fecha,
    required this.unidadEntrada,
    this.cantidadFactura,
    this.cantidadReal,
    this.nFactura = '',
    this.nLote = '',
    this.fechaFabricacion,
    this.fechaVencimiento,
    this.senasac = '',
    this.transportador = '',
    this.precioTransporte,
    this.observaciones = '',
    this.fotos = const [],
  });
}
