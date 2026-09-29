import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../utils/texto.dart';
import '../models/almacen.dart';
import '../models/categoria_inv.dart';
import '../models/existencia_item.dart';
import '../models/item_inventario.dart';
import '../models/movimiento_inv.dart';
import '../models/unidad_medida.dart';
import '../repositories/inventario_repository.dart';

/// Cómo está un ítem según sus días de existencia y su stock mínimo.
enum SituacionStock { sinDatos, optimo, bajo, critico }

/// Cuántos ítems hay dentro de una categoría (con todas sus subcategorías) y
/// cuántos necesitan atención: lo que muestra cada tarjeta de navegación.
class ResumenCategoria {
  final int items;
  final int pedidos;
  final int criticos;
  const ResumenCategoria({this.items = 0, this.pedidos = 0, this.criticos = 0});
}

/// Reglas del inventario por almacenes: qué almacenes ve cada rol, filtros,
/// validaciones, semáforo y conteos. No conoce widgets.
class InventarioService extends ChangeNotifier {
  InventarioService(this._repo, this._usuario);

  final InventarioRepository _repo;
  final Usuario _usuario;

  List<Almacen> almacenes = [];
  String? almacenId;

  /// TODAS las categorías (de todos los almacenes): hace falta para mostrar
  /// la ruta completa de un ítem recibido de otra área. La navegación (ver
  /// [hijosDe]) se limita igual a lo relevante para el almacén actual.
  List<CategoriaInv> categorias = [];
  List<ExistenciaItem> existencias = [];
  Set<int> _relevantes = {};

  int? categoriaFiltro;
  String busqueda = '';
  bool soloPedido = false;

  /// En la raíz solo se ven las categorías; con esto se lista todo el almacén.
  bool verTodo = false;

  bool cargando = true;
  String? error;

  // ---------------------------------------------------------------- permisos

  bool _puede(String accion, [String? almacen]) => _usuario.puede(
      Modulo.inventarioDe(almacen ?? almacenId ?? ''), accion,
      reglaAnterior: false);

  bool get puedeEditar => almacenId != null && _puede(Accion.editar);
  bool get puedeCrear => almacenId != null && _puede(Accion.crear);
  bool get puedeEliminar => almacenId != null && _puede(Accion.eliminar);

  /// La salida directa (sin pedido ni firma) es una acción de Almacén
  /// General sobre lo que tiene en su estante (sección 13 del md).
  bool get puedeSalidaDirecta => almacenId == 'general' && puedeEditar;

  // ------------------------------------------------------------------- carga

  Future<void> iniciar({String? almacenPreferido}) async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final todos = await _repo.almacenes();
      almacenes = [
        for (final a in todos)
          if (_puede(Accion.ver, a.id)) a
      ];
      if (almacenes.isEmpty) {
        cargando = false;
        notifyListeners();
        return;
      }
      final inicial = almacenes.any((a) => a.id == almacenPreferido)
          ? almacenPreferido!
          : almacenes.first.id;
      await _cargarAlmacen(inicial);
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
    } catch (e) {
      _fallo(e);
    }
  }

  Future<void> recargar() async {
    if (almacenId == null) return;
    try {
      await _cargarAlmacen(almacenId!);
    } catch (e) {
      _fallo(e);
    }
  }

  Future<void> _cargarAlmacen(String id) async {
    final resultados =
        await Future.wait([_repo.categoriasTodas(), _repo.existencias(id)]);
    almacenId = id;
    categorias = resultados[0] as List<CategoriaInv>;
    existencias = resultados[1] as List<ExistenciaItem>;
    _relevantes = _calcularRelevantes();
    if (categoriaFiltro != null && !_relevantes.contains(categoriaFiltro)) {
      categoriaFiltro = null;
    }
    cargando = false;
    error = null;
    notifyListeners();
  }

  /// Categorías propias del almacén actual: las únicas donde se pueden dar
  /// de alta ítems nuevos.
  List<CategoriaInv> get categoriasPropias =>
      categorias.where((c) => c.almacenId == almacenId).toList();

  CategoriaInv? _categoriaPorId(int id) {
    for (final c in categorias) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Propias (siempre, aunque estén vacías, para poder navegarlas y crear el
  /// primer ítem) + el camino completo hacia cualquier ítem recibido de otra
  /// área (ej. preformas que Soplado recibió de Almacén General).
  Set<int> _calcularRelevantes() {
    final ids = {for (final c in categoriasPropias) c.id};
    for (final e in existencias) {
      var actual = e.categoriaId as int?;
      while (actual != null && ids.add(actual)) {
        actual = _categoriaPorId(actual)?.padreId;
      }
    }
    return ids;
  }

  void _fallo(Object e) {
    cargando = false;
    error = 'No se pudo cargar el inventario. Revisá la conexión o que la '
        'migración v18 esté ejecutada.';
    if (kDebugMode) debugPrint('InventarioService: $e');
    notifyListeners();
  }

  // ---------------------------------------------------------------- filtros

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  void filtrarCategoria(int? id) {
    categoriaFiltro = id;
    notifyListeners();
  }

  void alternarSoloPedido() {
    soloPedido = !soloPedido;
    notifyListeners();
  }

  void alternarVerTodo() {
    verTodo = !verTodo;
    notifyListeners();
  }

  /// La lista de ítems aparece al entrar a una categoría, al buscar o al
  /// filtrar; en la raíz sin nada de eso se muestran solo las categorías.
  bool get mostrarTabla =>
      categoriaFiltro != null || busqueda.trim().isNotEmpty || soloPedido || verTodo;

  List<CategoriaInv> hijosDe(int? padreId) => categorias
      .where((c) => c.padreId == padreId && _relevantes.contains(c.id))
      .toList();

  /// Camino desde la raíz hasta [id]: [PET, Tapas, Tapa Short].
  List<CategoriaInv> rutaDe(int id) {
    final ruta = <CategoriaInv>[];
    int? actual = id;
    while (actual != null) {
      final c = categorias.where((c) => c.id == actual).firstOrNull;
      if (c == null) break;
      ruta.insert(0, c);
      actual = c.padreId;
    }
    return ruta;
  }

  String textoRuta(int categoriaId) =>
      rutaDe(categoriaId).map((c) => c.nombre).join(' › ');

  /// Ubicación de un ítem por debajo de la categoría abierta: dentro de
  /// "Tapas" se lee "PET › Tapa Short › Negro"; en la raíz, la ruta completa.
  String textoRutaRelativa(int categoriaId) {
    final ruta = rutaDe(categoriaId);
    if (categoriaFiltro == null) return ruta.map((c) => c.nombre).join(' › ');
    final desde = ruta.indexWhere((c) => c.id == categoriaFiltro);
    final resto = desde < 0 ? ruta : ruta.sublist(desde + 1);
    return resto.map((c) => c.nombre).join(' › ');
  }

  /// Ítems, pedidos y críticos de una categoría y todo lo que cuelga de ella.
  ResumenCategoria resumenDe(int categoriaId) {
    final ids = _idsConDescendientes(categoriaId);
    var items = 0, pedidos = 0, criticos = 0;
    for (final e in existencias) {
      if (!ids.contains(e.categoriaId)) continue;
      items++;
      if (necesitaPedido(e)) pedidos++;
      if (situacion(e) == SituacionStock.critico) criticos++;
    }
    return ResumenCategoria(items: items, pedidos: pedidos, criticos: criticos);
  }

  Set<int> _idsConDescendientes(int id) {
    final ids = {id};
    var pendientes = [id];
    while (pendientes.isNotEmpty) {
      final hijos = categorias
          .where((c) => c.padreId != null && pendientes.contains(c.padreId))
          .map((c) => c.id)
          .toList();
      ids.addAll(hijos);
      pendientes = hijos;
    }
    return ids;
  }

  /// Palabras de la búsqueda actual (sin tildes, minúsculas), para exigir
  /// que TODAS aparezcan (en cualquier orden, en detalle o código) — así
  /// "tapa negra" encuentra "Tapa Short Negra" aunque no sea ese el orden.
  List<String> get _palabrasBusqueda =>
      sinTildes(busqueda.trim()).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

  /// Si hay algo escrito en el buscador, se busca en TODO el almacén, no
  /// solo dentro de la categoría abierta: no debería hacer falta saber en
  /// qué categoría está un ítem para poder encontrarlo escribiendo su
  /// nombre. Al borrar la búsqueda se vuelve a ver la categoría de antes.
  bool get buscandoEnTodoElAlmacen => categoriaFiltro != null && _palabrasBusqueda.isNotEmpty;

  /// Ítems que pasan la categoría, la búsqueda y el filtro "Pedido".
  List<ExistenciaItem> get visibles {
    final palabras = _palabrasBusqueda;
    final ids = (categoriaFiltro != null && palabras.isEmpty)
        ? _idsConDescendientes(categoriaFiltro!)
        : null;
    return existencias.where((e) {
      if (ids != null && !ids.contains(e.categoriaId)) return false;
      if (soloPedido && !necesitaPedido(e)) return false;
      if (palabras.isEmpty) return true;
      final texto = '${sinTildes(e.detalle)} ${sinTildes(e.codigo)}';
      return palabras.every((p) => texto.contains(p));
    }).toList();
  }

  // --------------------------------------------------------------- semáforo

  SituacionStock situacion(ExistenciaItem e) {
    final dias = e.diasExistencia;
    if (dias == null) return SituacionStock.sinDatos;
    switch (SemaforoStock.evaluar(dias)) {
      case EstadoStock.critico:
        return SituacionStock.critico;
      case EstadoStock.bajo:
        return SituacionStock.bajo;
      case EstadoStock.optimo:
        return SituacionStock.optimo;
    }
  }

  /// Marca "Pedido" cuando el stock llegó al mínimo definido para el ítem.
  bool necesitaPedido(ExistenciaItem e) =>
      e.stockMinimo != null && e.cantidadSistema <= e.stockMinimo!;

  // ---------------------------------------------------------------- acciones

  Future<ItemInventario> cargarItem(int id) => _repo.item(id);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> guardarItem(ItemInventario item) async {
    final error = _validarItem(item);
    if (error != null) return error;
    final permiso = item.id == null ? puedeCrear : puedeEditar;
    if (!permiso) return 'No tenés permiso para modificar este almacén.';
    try {
      if (item.id == null) {
        await _repo.crearItem(item);
      } else {
        await _repo.actualizarItem(item);
      }
      await recargar();
      return null;
    } catch (e) {
      return _mensaje(e, 'No se pudo guardar el ítem.');
    }
  }

  Future<String?> desactivarItem(int id) async {
    if (!puedeEliminar) return 'No tenés permiso para eliminar ítems.';
    try {
      await _repo.desactivarItem(id);
      await recargar();
      return null;
    } catch (e) {
      return _mensaje(e, 'No se pudo eliminar el ítem.');
    }
  }

  /// Registra el conteo físico; el servidor guarda la diferencia contra el
  /// sistema como ajuste.
  Future<String?> registrarConteo(
    ExistenciaItem item, {
    required double cantidadReal,
    String? observaciones,
  }) async {
    if (!puedeEditar) return 'No tenés permiso para contar en este almacén.';
    if (cantidadReal.isNaN || cantidadReal < 0) {
      return 'La cantidad real no puede ser negativa.';
    }
    final obs = observaciones?.trim();
    if (obs != null && obs.length > 300) return 'Las observaciones son demasiado largas.';
    try {
      await _repo.registrarConteo(
        itemId: item.itemId,
        almacenId: item.almacenId,
        cantidadReal: cantidadReal,
        observaciones: (obs == null || obs.isEmpty) ? null : obs,
      );
      await recargar();
      return null;
    } catch (e) {
      return _mensaje(e, 'No se pudo registrar el conteo.');
    }
  }

  // ------------------------------------------------------------- movimientos

  Future<List<MovimientoInv>> movimientosDe(ExistenciaItem item) =>
      _repo.movimientos(item.itemId, item.almacenId);

  /// Ingreso o salida manual (saldo inicial, consumo, rotura…). El servidor
  /// vuelve a validar todo; acá se evita el viaje si ya se ve el error.
  Future<String?> registrarMovimiento(
    ExistenciaItem item, {
    required String tipo,
    required double? cantidad,
    required String motivo,
  }) async {
    if (!puedeEditar) return 'No tenés permiso para mover stock en este almacén.';
    if (tipo != 'entrada' && tipo != 'salida') return 'Elegí si es un ingreso o una salida.';
    if (cantidad == null || cantidad.isNaN || cantidad <= 0) {
      return 'La cantidad debe ser mayor a cero.';
    }
    final m = motivo.trim();
    if (m.length < 3) return 'Escribí el motivo (mínimo 3 caracteres).';
    if (m.length > 300) return 'El motivo es demasiado largo.';
    if (tipo == 'salida' && cantidad > item.cantidadSistema + 1e-9) {
      return 'Stock insuficiente: hay ${_n(item.cantidadSistema)} ${item.unidad} '
          'y se quieren sacar ${_n(cantidad)}.';
    }
    return _ejecutar(() => _repo.registrarMovimiento(
        itemId: item.itemId,
        almacenId: item.almacenId,
        tipo: tipo,
        cantidad: cantidad,
        motivo: m));
  }

  /// Anula un movimiento manual con un contra-asiento (el original queda en
  /// el historial).
  Future<String?> revertirMovimiento(MovimientoInv mov, String motivo) async {
    if (!puedeEditar) return 'No tenés permiso para revertir movimientos.';
    if (!mov.esManual) {
      return 'Solo se revierten movimientos manuales. Los de recepción, entrega o '
          'conteo se corrigen desde su propio módulo.';
    }
    if (mov.revertido) return 'Ese movimiento ya fue revertido.';
    final m = motivo.trim();
    if (m.length < 3) return 'Escribí el motivo (mínimo 3 caracteres).';
    if (m.length > 300) return 'El motivo es demasiado largo.';
    return _ejecutar(() => _repo.revertirMovimiento(mov.id, m));
  }

  /// Salida sin pedido formal ni firma (ej. termocontraíbles): el peso real
  /// es lo que descuenta stock; la cantidad de rollos es solo referencia.
  Future<String?> registrarSalidaDirecta({
    required ExistenciaItem? item,
    required String? areaDestino,
    required double? pesoReal,
    double? cantidadRollos,
    String? motivo,
  }) async {
    if (!puedeSalidaDirecta) return 'No tenés permiso para registrar salidas directas.';
    if (item == null) return 'Elegí el ítem.';
    if (areaDestino == null || areaDestino.isEmpty) return 'Elegí el área que lo recibe.';
    if (pesoReal == null || pesoReal.isNaN || pesoReal <= 0) {
      return 'El peso real debe ser mayor a cero.';
    }
    if (pesoReal > item.cantidadSistema + 1e-9) {
      return 'Stock insuficiente: hay ${_n(item.cantidadSistema)} ${item.unidad}.';
    }
    if (cantidadRollos != null && (cantidadRollos.isNaN || cantidadRollos <= 0)) {
      return 'La cantidad de rollos debe ser mayor a cero.';
    }
    if ((motivo?.length ?? 0) > 300) return 'El motivo es demasiado largo.';
    return _ejecutar(() => _repo.registrarSalidaDirecta(
        itemId: item.itemId,
        areaDestino: areaDestino,
        pesoReal: pesoReal,
        cantidadRollos: cantidadRollos,
        motivo: (motivo?.trim().isEmpty ?? true) ? null : motivo!.trim(),
        almacenId: item.almacenId));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioInventario catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('InventarioService: $e');
      return _mensaje(e, 'No se pudo completar la operación.');
    }
  }

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ------------------------------------------------------------ validaciones

  String? _validarItem(ItemInventario i) {
    final detalle = i.detalle.trim();
    if (detalle.isEmpty) return 'El detalle es obligatorio.';
    if (detalle.length > 120) return 'El detalle es demasiado largo (máx. 120).';
    if (!categoriasPropias.any((c) => c.id == i.categoriaId)) {
      return 'Elegí una categoría propia de este almacén.';
    }
    if (!UnidadMedida.todas.contains(i.unidad)) return 'Unidad de medida inválida.';
    final tieneCompra = (i.unidadCompra ?? '').trim().isNotEmpty;
    if (tieneCompra && (i.factorCompra == null || i.factorCompra! <= 0)) {
      return 'Indicá cuántas ${i.unidad} trae cada ${i.unidadCompra!.trim()}.';
    }
    if (i.unidadesPorCaja != null && i.unidadesPorCaja! <= 0) {
      return 'Las unidades por caja deben ser mayores a 0.';
    }
    if (i.stockMinimo != null && i.stockMinimo! < 0) {
      return 'El stock mínimo no puede ser negativo.';
    }
    if (i.consumoDiarioManual != null && i.consumoDiarioManual! < 0) {
      return 'El consumo diario no puede ser negativo.';
    }
    return null;
  }

  String _mensaje(Object e, String porDefecto) {
    final t = e.toString().toLowerCase();
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para hacer esto.';
    }
    if (t.contains('duplicate key') || t.contains('unique')) {
      return 'Ya existe un ítem con ese detalle en esa categoría.';
    }
    if (t.contains('timeout') || t.contains('socket')) {
      return 'Sin conexión. Intentá de nuevo.';
    }
    return porDefecto;
  }
}
