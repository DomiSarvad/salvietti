import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../utils/texto.dart';
import '../../inventario/models/unidad_medida.dart';
import '../models/recepciones_modelos.dart';
import '../repositories/recepciones_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';

enum VistaRecepciones { lista, reclamos }

/// Reglas de las recepciones de Almacén: qué almacenes ve y en cuáles puede
/// recibir cada rol, validación del formulario, conversión de unidades,
/// SENASAG automático y reclamos por diferencia de peso. No conoce widgets.
/// Campos del formulario de recepción que pueden tener un error.
enum CampoRecepcion {
  item, cantidadFactura, cantidadReal, unidad, fecha, fabricacion, vencimiento,
  precio, factura, lote, transportador, observaciones, senasac, fotos,
}

class RecepcionesService extends ChangeNotifier {
  RecepcionesService(this._repo, this._usuario, {DateTime Function()? ahora})
      : _ahora = ahora ?? DateTime.now;

  static const maxFotoBytes = 5 * 1024 * 1024;
  static const extensionesFoto = ['jpg', 'jpeg', 'png', 'webp'];
  static const maxFotos = 6;
  static final _formatoSenasac = RegExp(r'^[A-Za-z0-9\-./ ]+$');

  final RecepcionesRepository _repo;
  final Usuario _usuario;
  final DateTime Function() _ahora;

  List<AlmacenRec> almacenes = [];
  String? almacenId;
  List<RecepcionDetalle> recepciones = [];
  String busqueda = '';
  bool soloConDiferencia = false;

  VistaRecepciones vista = VistaRecepciones.lista;
  DateTime mesReclamos = DateTime(0);
  List<DiferenciaMes> reclamos = [];

  bool cargando = true;
  String? error;

  final Map<String, List<ItemRecepcion>> _items = {};
  List<Proveedor>? _proveedores;

  // ---------------------------------------------------------------- permisos

  bool _puede(String modulo, String accion) =>
      _usuario.puede(modulo, accion, reglaAnterior: false);

  /// Puede recibir en ese almacén: permiso de Recepciones y de operar el almacén.
  bool puedeRecibirEn(String almacen) =>
      _puede(Modulo.recepciones, Accion.crear) &&
      _puede(Modulo.inventarioDe(almacen), Accion.editar);

  bool get puedeRecibir => almacenId != null && puedeRecibirEn(almacenId!);

  // ------------------------------------------------------------------- carga

  Future<void> iniciar() async {
    mesReclamos = DateTime(_ahora().year, _ahora().month);
    cargando = true;
    error = null;
    notifyListeners();
    try {
      if (!_puede(Modulo.recepciones, Accion.ver)) {
        almacenes = [];
        cargando = false;
        notifyListeners();
        return;
      }
      final todos = await _repo.almacenes();
      almacenes = [
        for (final a in todos)
          if (_puede(Modulo.inventarioDe(a.id), Accion.ver)) a
      ];
      if (almacenes.isNotEmpty) await _cargarAlmacen(almacenes.first.id);
      cargando = false;
      notifyListeners();
    } catch (e) {
      _fallo(e);
    }
  }

  Future<void> seleccionarAlmacen(String id) async {
    if (id == almacenId) return;
    cargando = true;
    notifyListeners();
    try {
      await _cargarAlmacen(id);
      cargando = false;
      notifyListeners();
    } catch (e) {
      _fallo(e);
    }
  }

  Future<void> recargar() async {
    if (almacenId == null) return;
    try {
      await _cargarAlmacen(almacenId!);
      notifyListeners();
    } catch (e) {
      _fallo(e);
    }
  }

  Future<void> _cargarAlmacen(String id) async {
    // Las dos consultas a la vez, no una detrás de la otra.
    final conReclamos = vista == VistaRecepciones.reclamos;
    final r = await Future.wait([
      _repo.recepciones(id),
      if (conReclamos) _repo.diferenciasDelMes(id, mesReclamos),
    ]);
    recepciones = r[0] as List<RecepcionDetalle>;
    almacenId = id;
    error = null;
    if (conReclamos) reclamos = r[1] as List<DiferenciaMes>;
  }

  void _fallo(Object e) {
    cargando = false;
    error = 'No se pudieron cargar las recepciones. Revisá la conexión o que '
        'la migración v20 esté ejecutada.';
    if (kDebugMode) debugPrint('RecepcionesService: $e');
    notifyListeners();
  }

  // ---------------------------------------------------------------- filtros

  /// Buscador común (texto + Desde/Hasta): define qué se ve y qué sale en el
  /// reporte PDF/Excel.
  FiltroLista filtro = const FiltroLista();

  void filtrar(FiltroLista f) {
    filtro = f;
    busqueda = f.texto;
    notifyListeners();
  }

  void buscar(String texto) => filtrar(filtro.conTexto(texto));

  void alternarSoloConDiferencia() {
    soloConDiferencia = !soloConDiferencia;
    notifyListeners();
  }

  /// Busca en código, ítem, proveedor, factura, lote y transportador: todas
  /// las palabras, en cualquier orden.
  List<RecepcionDetalle> get visibles => filtro.aplicar(
        recepciones.where((r) => !soloConDiferencia || r.diferencia.abs() >= 1e-9),
        texto: (r) => <String?>[r.codigo, r.detalle, r.proveedor, r.nFactura, r.nLote, r.transportador]
            .whereType<String>()
            .join(' '),
        fecha: (r) => r.fecha,
      );

  ReporteTabla reporte() => ReporteTabla(
        titulo: 'Recepciones',
        filtros: [
          filtro.describir(),
          if (soloConDiferencia) 'Solo con diferencia',
        ].join('   ·   '),
        columnas: const [
          'Fecha', 'Código', 'Ítem', 'Proveedor', 'Factura', 'Cant. factura', 'Cant. real',
          'Diferencia', 'Unidad', 'Lote', 'Vence',
        ],
        filas: [
          for (final r in visibles)
            [
              r.fecha, r.codigo, r.detalle, r.proveedor, r.nFactura, r.cantidadFactura, r.cantidadReal,
              r.diferencia, r.unidad, r.nLote, r.fechaVencimiento,
            ]
        ],
      );

  Future<void> cambiarVista(VistaRecepciones nueva) async {
    if (vista == nueva) return;
    vista = nueva;
    notifyListeners();
    if (nueva == VistaRecepciones.reclamos) await cargarReclamos(mesReclamos);
  }

  Future<void> cargarReclamos(DateTime mes) async {
    if (almacenId == null) return;
    mesReclamos = DateTime(mes.year, mes.month);
    try {
      reclamos = await _repo.diferenciasDelMes(almacenId!, mesReclamos);
      error = null;
    } catch (e) {
      error = 'No se pudieron cargar los reclamos.';
      if (kDebugMode) debugPrint('RecepcionesService: $e');
    }
    notifyListeners();
  }

  /// Solo los proveedores/ítems que faltaron producto (diferencia negativa).
  List<DiferenciaMes> get reclamosConFaltante =>
      reclamos.where((d) => d.diferencia < -1e-9).toList();

  // ----------------------------------------------------- datos del formulario

  Future<List<ItemRecepcion>> itemsDe(String almacen) async =>
      _items[almacen] ??= await _repo.itemsDelAlmacen(almacen);

  Future<List<Proveedor>> proveedores() async =>
      _proveedores ??= await _repo.proveedores();

  /// Devuelve el proveedor creado, o el que ya existía con ese nombre.
  /// Null solo significa "nombre inválido" (2 a 80 caracteres); un error de
  /// conexión o de permisos se deja subir como excepción, para no
  /// mostrarle al usuario el mismo mensaje de "nombre inválido" cuando en
  /// realidad fue un problema de red.
  Future<Proveedor?> crearProveedor(String nombre) async {
    final limpio = nombre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpio.length < 2 || limpio.length > 80) return null;
    final lista = await proveedores();
    final existente =
        lista.where((p) => sinTildes(p.nombre) == sinTildes(limpio)).firstOrNull;
    if (existente != null) return existente;
    final nuevo = await _repo.crearProveedor(limpio);
    _proveedores = [...lista, nuevo]..sort((a, b) => a.nombre.compareTo(b.nombre));
    return nuevo;
  }

  /// SENASAG ya conocido para ese producto y proveedor, para rellenar solo.
  Future<String?> senasacSugerido(int itemId, int proveedorId) async {
    try {
      return await _repo.senasacDe(itemId, proveedorId);
    } catch (_) {
      return null;
    }
  }

  Future<String?> urlFoto(String ruta) async {
    try {
      return await _repo.urlFoto(ruta);
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------- guardar

  /// Convierte lo escrito a la unidad del ítem. Null si falta un dato.
  static double? aUnidadItem(double? valor, String entrada, String unidadItem) =>
      valor == null ? null : UnidadMedida.convertir(valor, de: entrada, a: unidadItem);

  /// Diferencia (real − factura) en la unidad del ítem, para mostrarla mientras se escribe.
  static double? diferenciaDe(BorradorRecepcion b) {
    if (b.item == null) return null;
    final f = aUnidadItem(b.cantidadFactura, b.unidadEntrada, b.item!.unidad);
    final r = aUnidadItem(b.cantidadReal, b.unidadEntrada, b.item!.unidad);
    return (f == null || r == null) ? null : r - f;
  }

  /// Valida y guarda. Devuelve null si salió bien, o el mensaje de error.
  Future<String?> guardar(BorradorRecepcion b) async {
    campoConError = null;
    if (!puedeRecibirEn(b.almacenId)) {
      return 'No tenés permiso para registrar recepciones en este almacén.';
    }
    final error = _validar(b);
    if (error != null) return error;

    final item = b.item!;
    final rutas = <String>[];
    try {
      for (final foto in b.fotos) {
        rutas.add(await _repo.subirFoto(
          foto.bytes,
          ruta: _rutaFoto(b, foto),
          contentType: foto.extension == 'png'
              ? 'image/png'
              : (foto.extension == 'webp' ? 'image/webp' : 'image/jpeg'),
        ));
      }
      String? texto(String t) => t.trim().isEmpty ? null : t.trim();
      await _repo.crearRecepcion(RecepcionNueva(
        almacenId: b.almacenId,
        itemId: item.id,
        proveedorId: b.proveedor?.id,
        fecha: DateTime(b.fecha.year, b.fecha.month, b.fecha.day),
        nFactura: texto(b.nFactura),
        cantidadFactura: aUnidadItem(b.cantidadFactura, b.unidadEntrada, item.unidad)!,
        cantidadReal: aUnidadItem(b.cantidadReal, b.unidadEntrada, item.unidad)!,
        nLote: texto(b.nLote),
        fechaFabricacion: b.fechaFabricacion,
        fechaVencimiento: b.fechaVencimiento,
        senasac: texto(b.senasac),
        transportador: texto(b.transportador),
        precioTransporte: b.precioTransporte,
        fotos: rutas,
        observaciones: texto(b.observaciones),
      ));
      await recargar();
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('RecepcionesService.guardar: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('row-level security') || t.contains('permission denied')) {
        return 'No tenés permiso para hacer esto.';
      }
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se guardó la recepción; intentá de nuevo.';
      }
      return 'No se pudo guardar la recepción.';
    }
  }

  String _rutaFoto(BorradorRecepcion b, FotoAdjunta foto) {
    final f = b.fecha;
    final mes = '${f.year}-${f.month.toString().padLeft(2, '0')}';
    final azar = Random.secure().nextInt(1 << 31).toRadixString(16);
    final ext = foto.extension == 'jpeg' ? 'jpg' : foto.extension;
    return '${b.almacenId}/$mes/${_ahora().microsecondsSinceEpoch}_$azar.$ext';
  }

  /// El campo del último error de [guardar] (null si no fue de un campo): la
  /// pantalla lo señala con un globo, como la validación de un navegador.
  CampoRecepcion? campoConError;

  String _falla(CampoRecepcion campo, String mensaje) {
    campoConError = campo;
    return mensaje;
  }

  String? _validar(BorradorRecepcion b) {
    campoConError = null;
    final item = b.item;
    if (item == null) return _falla(CampoRecepcion.item, 'Elegí el ítem que llegó.');
    if (item.almacenId != b.almacenId) return _falla(CampoRecepcion.item, 'Ese ítem no pertenece a este almacén.');

    if (b.cantidadFactura == null || b.cantidadFactura! <= 0) {
      return _falla(CampoRecepcion.cantidadFactura, 'Escribí la cantidad que dice la factura o la etiqueta.');
    }
    if (b.cantidadReal == null || b.cantidadReal! <= 0) {
      return _falla(CampoRecepcion.cantidadReal, 'Escribí el peso o la cantidad real que contaste.');
    }
    final posibles = item.unidad == 'KG'
        ? const ['KG', 'GR']
        : (item.unidad == 'L' ? const ['L', 'ML'] : [item.unidad]);
    if (!posibles.contains(b.unidadEntrada)) return _falla(CampoRecepcion.unidad, 'Unidad no válida para este ítem.');

    final hoy = DateTime(_ahora().year, _ahora().month, _ahora().day);
    final fecha = DateTime(b.fecha.year, b.fecha.month, b.fecha.day);
    if (fecha.isAfter(hoy)) return _falla(CampoRecepcion.fecha, 'La fecha de recepción no puede ser futura.');

    final fab = b.fechaFabricacion;
    final ven = b.fechaVencimiento;
    if (fab != null && fab.isAfter(hoy)) return _falla(CampoRecepcion.fabricacion, 'La fecha de fabricación no puede ser futura.');
    if (fab != null && ven != null && !ven.isAfter(fab)) {
      return _falla(CampoRecepcion.vencimiento, 'El vencimiento debe ser posterior a la fabricación.');
    }
    if (ven != null && ven.isBefore(fecha)) {
      return _falla(CampoRecepcion.vencimiento, 'El producto llegó vencido: revisá la fecha de vencimiento.');
    }

    if (b.precioTransporte != null && b.precioTransporte! < 0) {
      return _falla(CampoRecepcion.precio, 'El precio del transporte no puede ser negativo.');
    }
    if (b.nFactura.trim().length > 40) return _falla(CampoRecepcion.factura, 'El N° de factura es demasiado largo.');
    if (b.nLote.trim().length > 40) return _falla(CampoRecepcion.lote, 'El N° de lote es demasiado largo.');
    if (b.transportador.trim().length > 80) return _falla(CampoRecepcion.transportador, 'El nombre del transportador es demasiado largo.');
    if (b.observaciones.trim().length > 300) return _falla(CampoRecepcion.observaciones, 'Las observaciones son demasiado largas.');

    final senasac = b.senasac.trim();
    if (senasac.length > 40 || (senasac.isNotEmpty && !_formatoSenasac.hasMatch(senasac))) {
      return _falla(CampoRecepcion.senasac, 'El código SENASAG solo puede tener letras, números, guiones, puntos y barras.');
    }

    if (b.fotos.length > maxFotos) return _falla(CampoRecepcion.fotos, 'Se pueden adjuntar hasta $maxFotos fotos.');
    for (final foto in b.fotos) {
      if (!extensionesFoto.contains(foto.extension)) {
        return _falla(CampoRecepcion.fotos, 'Las fotos deben ser JPG, PNG o WEBP (${foto.nombre}).');
      }
      if (foto.bytes.length > maxFotoBytes) return _falla(CampoRecepcion.fotos, 'La foto ${foto.nombre} pesa más de 5 MB.');
    }
    return null;
  }
}
