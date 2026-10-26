// Modelos del módulo de Soplado.

class ErrorNegocioSoplado implements Exception {
  final String mensaje;
  const ErrorNegocioSoplado(this.mensaje);
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

class Presentacion {
  final int id;
  final String nombre;
  final String material;
  const Presentacion({required this.id, required this.nombre, required this.material});
  factory Presentacion.fromMap(Map<String, dynamic> m) => Presentacion(
        id: (m['id'] as num).toInt(),
        nombre: m['nombre'] as String,
        material: m['material'] as String,
      );
}

/// Ítem del catálogo (preforma) que se puede elegir para una corrida.
class ItemPreforma {
  final int id;
  final String codigo;
  final String detalle;
  final String unidad;
  const ItemPreforma(
      {required this.id, required this.codigo, required this.detalle, required this.unidad});
  factory ItemPreforma.fromMap(Map<String, dynamic> m) => ItemPreforma(
        id: (m['id'] as num).toInt(),
        codigo: (m['codigo'] as String?) ?? '',
        detalle: m['detalle'] as String,
        unidad: m['unidad'] as String,
      );
}

/// Proveedor de la preforma (misma tabla `inv_proveedores` que Recepciones).
class Proveedor {
  final int id;
  final String nombre;
  const Proveedor({required this.id, required this.nombre});
  factory Proveedor.fromMap(Map<String, dynamic> m) =>
      Proveedor(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

enum EstadoCorrida {
  enCurso('en_curso', 'En curso'),
  finalizada('finalizada', 'Finalizada'),
  anulada('anulada', 'Anulada');

  final String id;
  final String etiqueta;
  const EstadoCorrida(this.id, this.etiqueta);
  static EstadoCorrida desde(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => EstadoCorrida.enCurso);
}

class CorridaSoplado {
  final int id;
  final DateTime fecha;
  final int saborId;
  final String? sabor;
  final int presentacionId;
  final String? presentacion;
  final int? itemPreformaId;
  final String? itemPreformaDetalle;
  final String? itemPreformaUnidad;
  final int? proveedorId;
  final String? proveedorNombre;
  final String? lotePreforma;
  final EstadoCorrida estado;
  final DateTime horaInicio;
  final DateTime? horaFin;
  final double? botellasSopladas;
  final double? preformasUsadas;
  final double? botellasEtiquetadas;
  final int mermaSoplado;
  final int mermaPreforma;
  final int mermaEtiquetado;
  final int? tiempoParadaMinutos;
  final String? motivoParada;
  final String? motivoMerma;
  final String? observaciones;
  final String? responsableNombre;

  const CorridaSoplado({
    required this.id,
    required this.fecha,
    required this.saborId,
    this.sabor,
    required this.presentacionId,
    this.presentacion,
    this.itemPreformaId,
    this.itemPreformaDetalle,
    this.itemPreformaUnidad,
    this.proveedorId,
    this.proveedorNombre,
    this.lotePreforma,
    required this.estado,
    required this.horaInicio,
    this.horaFin,
    this.botellasSopladas,
    this.preformasUsadas,
    this.botellasEtiquetadas,
    this.mermaSoplado = 0,
    this.mermaPreforma = 0,
    this.mermaEtiquetado = 0,
    this.tiempoParadaMinutos,
    this.motivoParada,
    this.motivoMerma,
    this.observaciones,
    this.responsableNombre,
  });

  Duration? get duracion => horaFin?.difference(horaInicio);

  /// Iniciado sin internet y todavía en la cola (id provisorio negativo).
  bool get sinSubir => id < 0;
  bool get tieneMerma => mermaSoplado > 0 || mermaPreforma > 0 || mermaEtiquetado > 0;

  /// Botellas buenas que quedaron después de soplar y etiquetar.
  double? get botellasBuenas => botellasSopladas == null
      ? null
      : botellasSopladas! - mermaSoplado - mermaEtiquetado;

  factory CorridaSoplado.fromMap(Map<String, dynamic> m) {
    final sabor = m['sabores'] as Map?;
    final presentacion = m['presentaciones'] as Map?;
    final item = m['inv_items'] as Map?;
    final proveedor = m['inv_proveedores'] as Map?;
    return CorridaSoplado(
      id: (m['id'] as num).toInt(),
      fecha: DateTime.parse(m['fecha'] as String),
      saborId: (m['sabor_id'] as num).toInt(),
      sabor: sabor?['nombre'] as String?,
      presentacionId: (m['presentacion_id'] as num).toInt(),
      presentacion: presentacion?['nombre'] as String?,
      itemPreformaId: (m['item_preforma_id'] as num?)?.toInt(),
      itemPreformaDetalle: item?['detalle'] as String?,
      itemPreformaUnidad: item?['unidad'] as String?,
      proveedorId: (m['proveedor_id'] as num?)?.toInt(),
      proveedorNombre: proveedor?['nombre'] as String?,
      lotePreforma: m['lote_preforma'] as String?,
      estado: EstadoCorrida.desde(m['estado'] as String),
      horaInicio: DateTime.parse(m['hora_inicio'] as String).toLocal(),
      horaFin: m['hora_fin'] == null ? null : DateTime.parse(m['hora_fin'] as String).toLocal(),
      botellasSopladas: (m['botellas_sopladas'] as num?)?.toDouble(),
      preformasUsadas: (m['preformas_usadas'] as num?)?.toDouble(),
      botellasEtiquetadas: (m['botellas_etiquetadas'] as num?)?.toDouble(),
      mermaSoplado: (m['merma_soplado'] as num?)?.toInt() ?? 0,
      mermaPreforma: (m['merma_preforma'] as num?)?.toInt() ?? 0,
      mermaEtiquetado: (m['merma_etiquetado'] as num?)?.toInt() ?? 0,
      tiempoParadaMinutos: (m['tiempo_parada_minutos'] as num?)?.toInt(),
      motivoParada: m['motivo_parada'] as String?,
      motivoMerma: m['motivo_merma'] as String?,
      observaciones: m['observaciones'] as String?,
      responsableNombre: m['responsable_nombre'] as String?,
    );
  }
}

/// Avance de Soplado (últimos 14 días): botellas buenas y, si se conocen
/// las unidades por caja de la presentación, su equivalente en cajas.
class AvanceSoplado {
  final String sabor;
  final String presentacion;
  final int corridas;
  final double botellasBuenas;
  final double? cajasSopladas;
  final DateTime? ultimaCorrida;

  const AvanceSoplado({
    required this.sabor,
    required this.presentacion,
    required this.corridas,
    required this.botellasBuenas,
    this.cajasSopladas,
    this.ultimaCorrida,
  });

  factory AvanceSoplado.fromMap(Map<String, dynamic> m) => AvanceSoplado(
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String,
        corridas: (m['corridas'] as num).toInt(),
        botellasBuenas: (m['botellas_buenas'] as num).toDouble(),
        cajasSopladas: (m['cajas_sopladas'] as num?)?.toDouble(),
        ultimaCorrida:
            m['ultima_corrida'] == null ? null : DateTime.parse(m['ultima_corrida'] as String).toLocal(),
      );
}

class FinalizarCorrida {
  final double botellasSopladas;
  final double preformasUsadas;
  final int mermaSoplado;
  final int mermaPreforma;
  final double? botellasEtiquetadas;
  final int mermaEtiquetado;
  final int? tiempoParadaMinutos;
  final String? motivoParada;
  final String? motivoMerma;
  final String? observaciones;

  const FinalizarCorrida({
    required this.botellasSopladas,
    required this.preformasUsadas,
    this.mermaSoplado = 0,
    this.mermaPreforma = 0,
    this.botellasEtiquetadas,
    this.mermaEtiquetado = 0,
    this.tiempoParadaMinutos,
    this.motivoParada,
    this.motivoMerma,
    this.observaciones,
  });
}
