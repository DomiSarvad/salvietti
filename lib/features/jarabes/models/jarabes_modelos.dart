// Modelos del módulo de Recetas y producción de Jarabes.

class ErrorNegocioJarabes implements Exception {
  final String mensaje;
  const ErrorNegocioJarabes(this.mensaje);
  @override
  String toString() => mensaje;
}

class Sabor {
  final int id;
  final String nombre;
  const Sabor({required this.id, required this.nombre});
  factory Sabor.fromMap(Map<String, dynamic> m) =>
      Sabor(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

/// Ítem del Almacén de Jarabes, para armar una receta.
class ItemJarabes {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  const ItemJarabes(
      {required this.id, required this.codigo, required this.detalle, required this.unidad});
  factory ItemJarabes.fromMap(Map<String, dynamic> m) => ItemJarabes(
        id: (m['id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
      );
}

/// Una línea de la receta vigente de un sabor, con lo disponible ahora.
class ItemReceta {
  final int itemId;
  final String detalle;
  final String unidad;
  final double cantidadPorPreparado;
  final double disponible;
  const ItemReceta({
    required this.itemId,
    required this.detalle,
    required this.unidad,
    required this.cantidadPorPreparado,
    required this.disponible,
  });
  factory ItemReceta.fromMap(Map<String, dynamic> m) => ItemReceta(
        itemId: (m['item_id'] as num).toInt(),
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        cantidadPorPreparado: (m['cantidad_por_preparado'] as num).toDouble(),
        disponible: (m['disponible'] as num).toDouble(),
      );
}

enum EstadoReceta {
  propuesta('propuesta', 'Propuesta'),
  activa('activa', 'Activa'),
  inactiva('inactiva', 'Reemplazada'),
  rechazada('rechazada', 'Rechazada');

  final String id;
  final String etiqueta;
  const EstadoReceta(this.id, this.etiqueta);
  static EstadoReceta desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoReceta.propuesta);
}

class LineaRecetaPropuesta {
  final String detalle;
  final String unidad;
  final double cantidad;
  const LineaRecetaPropuesta({required this.detalle, required this.unidad, required this.cantidad});
  factory LineaRecetaPropuesta.fromMap(Map<String, dynamic> m) {
    final item = m['inv_items'] as Map;
    return LineaRecetaPropuesta(
      detalle: item['detalle'] as String,
      unidad: item['unidad'] as String,
      cantidad: (m['cantidad_por_preparado'] as num).toDouble(),
    );
  }
}

class RecetaPropuesta {
  final int id;
  final int saborId;
  final String? sabor;
  final EstadoReceta estado;
  final String? creadaPorNombre;
  final DateTime creadaEn;
  final String? motivoRechazo;
  final List<LineaRecetaPropuesta> items;
  final String? aprobadaCalidadNombre;
  final DateTime? aprobadaCalidadEn;
  final String? aprobadaProduccionNombre;
  final DateTime? aprobadaProduccionEn;

  const RecetaPropuesta({
    required this.id,
    required this.saborId,
    this.sabor,
    required this.estado,
    this.creadaPorNombre,
    required this.creadaEn,
    this.motivoRechazo,
    this.items = const [],
    this.aprobadaCalidadNombre,
    this.aprobadaCalidadEn,
    this.aprobadaProduccionNombre,
    this.aprobadaProduccionEn,
  });

  /// El cambio de receta lo aprueban Calidad Y Producción por separado;
  /// recién con las dos, el Gerente puede confirmarla con su clave.
  bool get tieneVistoBuenoCalidad => aprobadaCalidadEn != null;
  bool get tieneVistoBuenoProduccion => aprobadaProduccionEn != null;
  bool get listaParaGerente => tieneVistoBuenoCalidad && tieneVistoBuenoProduccion;

  factory RecetaPropuesta.fromMap(Map<String, dynamic> m) {
    final sabor = m['sabores'] as Map?;
    final items = (m['jarabes_receta_items'] as List?) ?? const [];
    return RecetaPropuesta(
      id: (m['id'] as num).toInt(),
      saborId: (m['sabor_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      estado: EstadoReceta.desde(m['estado'] as String),
      creadaPorNombre: m['creada_por_nombre'] as String?,
      creadaEn: DateTime.parse(m['creada_en'] as String).toLocal(),
      motivoRechazo: m['motivo_rechazo'] as String?,
      items: [
        for (final i in items) LineaRecetaPropuesta.fromMap(Map<String, dynamic>.from(i as Map))
      ],
      aprobadaCalidadNombre: m['aprobada_calidad_nombre'] as String?,
      aprobadaCalidadEn: m['aprobada_calidad_en'] == null
          ? null
          : DateTime.parse(m['aprobada_calidad_en'] as String).toLocal(),
      aprobadaProduccionNombre: m['aprobada_produccion_nombre'] as String?,
      aprobadaProduccionEn: m['aprobada_produccion_en'] == null
          ? null
          : DateTime.parse(m['aprobada_produccion_en'] as String).toLocal(),
    );
  }
}

/// Lo que hace falta para preparar [cantidad] veces la receta de un sabor.
class VerificacionInsumo {
  final int itemId;
  final String detalle;
  final String unidad;
  final double necesario;
  final double disponible;
  final double falta;
  const VerificacionInsumo({
    required this.itemId,
    required this.detalle,
    required this.unidad,
    required this.necesario,
    required this.disponible,
    required this.falta,
  });
  bool get alcanza => falta <= 0;
  factory VerificacionInsumo.fromMap(Map<String, dynamic> m) => VerificacionInsumo(
        itemId: (m['item_id'] as num).toInt(),
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
        necesario: (m['necesario'] as num).toDouble(),
        disponible: (m['disponible'] as num).toDouble(),
        falta: (m['falta'] as num).toDouble(),
      );
}

enum EstadoPreparado {
  enCurso('en_curso', 'En curso'),
  finalizada('finalizada', 'Finalizada'),
  anulada('anulada', 'Anulada');

  final String id;
  final String etiqueta;
  const EstadoPreparado(this.id, this.etiqueta);
  static EstadoPreparado desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoPreparado.enCurso);
}

class Preparado {
  final int id;
  final DateTime fecha;
  final int saborId;
  final String? sabor;
  final int nLote;
  final int? tanque;
  final double cantidadPreparados;
  final double? litros;
  final EstadoPreparado estado;
  final DateTime horaInicio;
  final DateTime? horaFin;
  final double? brix;
  final String? responsableNombre;
  final String? observaciones;

  const Preparado({
    required this.id,
    required this.fecha,
    required this.saborId,
    this.sabor,
    required this.nLote,
    this.tanque,
    required this.cantidadPreparados,
    this.litros,
    required this.estado,
    required this.horaInicio,
    this.horaFin,
    this.brix,
    this.responsableNombre,
    this.observaciones,
  });

  Duration? get duracion => horaFin?.difference(horaInicio);

  factory Preparado.fromMap(Map<String, dynamic> m) {
    final sabor = m['sabores'] as Map?;
    return Preparado(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String),
      saborId: (m['sabor_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      nLote: (m['n_lote'] as num).toInt(),
      tanque: (m['tanque'] as num?)?.toInt(),
      cantidadPreparados: (m['cantidad_preparados'] as num).toDouble(),
      litros: (m['litros'] as num?)?.toDouble(),
      estado: EstadoPreparado.desde(m['estado'] as String),
      horaInicio: DateTime.parse(m['hora_inicio'] as String).toLocal(),
      horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
      brix: (m['brix'] as num?)?.toDouble(),
      responsableNombre: m['responsable_nombre'] as String?,
      observaciones: m['observaciones'] as String?,
    );
  }
}

/// Avance de Soplado (vista `soplado_avance`), para no preparar de más.
class AvanceSopladoLite {
  final String sabor;
  final String presentacion;
  final double cajasSopladas;
  const AvanceSopladoLite(
      {required this.sabor, required this.presentacion, required this.cajasSopladas});
  factory AvanceSopladoLite.fromMap(Map<String, dynamic> m) => AvanceSopladoLite(
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String,
        cajasSopladas: (m['cajas_sopladas'] as num).toDouble(),
      );
}
