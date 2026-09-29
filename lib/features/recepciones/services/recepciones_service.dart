import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../utils/texto.dart';
import '../../inventario/models/unidad_medida.dart';
import '../models/recepciones_modelos.dart';
import '../repositories/recepciones_repository.dart';

enum VistaRecepciones { lista, reclamos }

/// Reglas de las recepciones de Almacén: qué almacenes ve y en cuáles puede
/// recibir cada rol, validación del formulario, conversión de unidades,
/// SENASAG automático y reclamos por diferencia de peso. No conoce widgets.
class RecepcionesService extends ChangeNotifier {
  RecepcionesService(this._repo, this._usuario, {DateTime Function()? ahora})
      : _ahora = ahora ?? DateTime.now;

  static const maxFotoBytes = 5 * 1024 * 1024;
  static const extensionesFoto = ['jpg', 'jpeg', 'png', 'webp'];
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
    recepciones = await _repo.recepciones(id);
    almacenId = id;
    error = null;
    if (vista == VistaRecepciones.reclamos) {
      reclamos = await _repo.diferenciasDelMes(id, mesReclamos);
    }
  }

  void _fallo(Object e) {
    cargando = false;
    error = 'No se pudieron cargar las recepciones. Revisá la conexión o que '
        'la migración v20 esté ejecutada.';
    if (kDebugMode) debugPrint('RecepcionesService: $e');
    notifyListeners();
  }

  // ---------------------------------------------------------------- filtros

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  void alternarSoloConDiferencia() {
    soloConDiferencia = !soloConDiferencia;
    notifyListeners();
  }

  List<RecepcionDetalle> get visibles {
    final q = sinTildes(busqueda.trim());
    return recepciones.where((r) {
      if (soloConDiferencia && r.diferencia.abs() < 1e-9) return false;
      if (q.isEmpty) return true;
      return sinTildes(r.detalle).contains(q) ||
          sinTildes(r.proveedor ?? '').contains(q) ||
          sinTildes(r.nFactura ?? '').contains(q) ||
          sinTildes(r.nLote ?? '').contains(q);
    }).toList();
  }

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
  Future<Proveedor?> crearProveedor(String nombre) async {
    final limpio = nombre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpio.length < 2 || limpio.length > 80) return null;
    final lista = await proveedores();
    final existente =
        lista.where((p) => sinTildes(p.nombre) == sinTildes(limpio)).firstOrNull;
    if (existente != null) return existente;
    try {
      final nuevo = await _repo.crearProveedor(limpio);
      _proveedores = [...lista, nuevo]..sort((a, b) => a.nombre.compareTo(b.nombre));
      return nuevo;
    } catch (_) {
      return null;
    }
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
    if (!puedeRecibirEn(b.almacenId)) {
      return 'No tenés permiso para registrar recepciones en este almacén.';
    }
    final error = _validar(b);
    if (error != null) return error;

    final item = b.item!;
    String? rutaFoto;
    try {
      if (b.foto != null) {
        rutaFoto = await _repo.subirFoto(
          b.foto!.bytes,
          ruta: _rutaFoto(b),
          contentType: b.foto!.extension == 'png'
              ? 'image/png'
              : (b.foto!.extension == 'webp' ? 'image/webp' : 'image/jpeg'),
        );
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
        fotoUrl: rutaFoto,
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

  String _rutaFoto(BorradorRecepcion b) {
    final f = b.fecha;
    final mes = '${f.year}-${f.month.toString().padLeft(2, '0')}';
    final azar = Random.secure().nextInt(1 << 31).toRadixString(16);
    final ext = b.foto!.extension == 'jpeg' ? 'jpg' : b.foto!.extension;
    return '${b.almacenId}/$mes/${_ahora().microsecondsSinceEpoch}_$azar.$ext';
  }

  String? _validar(BorradorRecepcion b) {
    final item = b.item;
    if (item == null) return 'Elegí el ítem que llegó.';
    if (item.almacenId != b.almacenId) return 'Ese ítem no pertenece a este almacén.';

    if (b.cantidadFactura == null || b.cantidadFactura! <= 0) {
      return 'Escribí la cantidad que dice la factura o la etiqueta.';
    }
    if (b.cantidadReal == null || b.cantidadReal! <= 0) {
      return 'Escribí el peso o la cantidad real que contaste.';
    }
    final posibles = item.unidad == 'KG'
        ? const ['KG', 'GR']
        : (item.unidad == 'L' ? const ['L', 'ML'] : [item.unidad]);
    if (!posibles.contains(b.unidadEntrada)) return 'Unidad no válida para este ítem.';

    final hoy = DateTime(_ahora().year, _ahora().month, _ahora().day);
    final fecha = DateTime(b.fecha.year, b.fecha.month, b.fecha.day);
    if (fecha.isAfter(hoy)) return 'La fecha de recepción no puede ser futura.';

    final fab = b.fechaFabricacion;
    final ven = b.fechaVencimiento;
    if (fab != null && fab.isAfter(hoy)) return 'La fecha de fabricación no puede ser futura.';
    if (fab != null && ven != null && !ven.isAfter(fab)) {
      return 'El vencimiento debe ser posterior a la fabricación.';
    }
    if (ven != null && ven.isBefore(fecha)) {
      return 'El producto llegó vencido: revisá la fecha de vencimiento.';
    }

    if (b.precioTransporte != null && b.precioTransporte! < 0) {
      return 'El precio del transporte no puede ser negativo.';
    }
    if (b.nFactura.trim().length > 40) return 'El N° de factura es demasiado largo.';
    if (b.nLote.trim().length > 40) return 'El N° de lote es demasiado largo.';
    if (b.transportador.trim().length > 80) return 'El nombre del transportador es demasiado largo.';
    if (b.observaciones.trim().length > 300) return 'Las observaciones son demasiado largas.';

    final senasac = b.senasac.trim();
    if (senasac.length > 40 || (senasac.isNotEmpty && !_formatoSenasac.hasMatch(senasac))) {
      return 'El código SENASAG solo puede tener letras, números, guiones, puntos y barras.';
    }

    final foto = b.foto;
    if (foto != null) {
      if (!extensionesFoto.contains(foto.extension)) {
        return 'La foto debe ser JPG, PNG o WEBP.';
      }
      if (foto.bytes.length > maxFotoBytes) return 'La foto pesa más de 5 MB.';
    }
    return null;
  }
}
