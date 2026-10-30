import 'dart:async';
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
import '../models/movimiento_periodo.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/comprobante_pdf.dart';
import '../../../shared/reportes/reporte_tabla.dart';
import '../../../utils/formatters.dart';
import '../models/unidad_medida.dart';
import '../repositories/inventario_repository.dart';
import '../models/conteo_nuevo.dart';
import 'excel_inventario.dart';

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

  /// Tipos elegidos en "Filtrar por tipo" (categorías de primer nivel del
  /// almacén). Varios a la vez, y se suman al buscador: así sale un reporte
  /// de, por ejemplo, solo Tapas y Preformas.
  Set<int> tiposFiltro = {};
  String busqueda = '';
  bool soloPedido = false;

  /// Buscador común (texto + Desde/Hasta + PDF/Excel). El texto es [busqueda];
  /// las fechas muestran los ítems que tuvieron movimiento en ese período, con
  /// cuánto entró y salió ([movimientoDe]).
  FiltroLista filtro = const FiltroLista();

  /// Entradas/salidas por ítem en el período elegido (null = sin fechas, o
  /// todavía cargando).
  Map<int, MovimientoPeriodo>? _periodo;
  bool cargandoPeriodo = false;
  String? errorPeriodo;
  int _pedidoPeriodo = 0;

  bool cargando = true;
  String? error;

  /// Filas de la tabla que se dibujan (una tabla con cientos de filas se
  /// arma entera de nuevo a cada cambio y hacía lenta toda la pantalla). El
  /// PDF y los contadores usan siempre [visibles] completo.
  static const filasPorTanda = 100;
  int limiteTabla = filasPorTanda;

  void mostrarMasFilas() {
    limiteTabla += filasPorTanda;
    notifyListeners();
  }

  Timer? _redibujarBusqueda;
  bool _cerrado = false;

  @override
  void dispose() {
    _redibujarBusqueda?.cancel();
    _cerrado = true;
    super.dispose();
  }

  // ------------------------------------------------------------- índices
  //
  // Se arman una vez por carga (no a cada letra ni por cada fila dibujada):
  // categoría por id, hijos por padre, descendientes, rutas, resumen de cada
  // tarjeta y el texto de búsqueda (sin tildes) de cada ítem. Se reconstruyen
  // solos si cambian las listas `categorias`/`existencias`.

  List<CategoriaInv>? _catsIndexadas;
  List<ExistenciaItem>? _existIndexadas;
  Map<int, CategoriaInv> _porId = {};
  Map<int?, List<CategoriaInv>> _hijosPorPadre = {};
  final Map<int, Set<int>> _descendientes = {};
  final Map<int, List<CategoriaInv>> _rutas = {};
  final Map<int, ResumenCategoria> _resumenes = {};
  final _textoBusqueda = Expando<String>();

  void _asegurarIndices() {
    if (!identical(_catsIndexadas, categorias)) {
      _catsIndexadas = categorias;
      _porId = {for (final c in categorias) c.id: c};
      _hijosPorPadre = {};
      for (final c in categorias) {
        (_hijosPorPadre[c.padreId] ??= []).add(c);
      }
      _descendientes.clear();
      _rutas.clear();
      _resumenes.clear();
      _visiblesMemo = null;
    }
    if (!identical(_existIndexadas, existencias)) {
      _existIndexadas = existencias;
      _resumenes.clear();
      _visiblesMemo = null;
    }
  }

  String _textoDe(ExistenciaItem e) =>
      _textoBusqueda[e] ??= '${sinTildes(e.detalle)} ${sinTildes(e.codigo)}';

  // Último resultado de [visibles] y con qué filtros se calculó.
  List<ExistenciaItem>? _visiblesMemo;
  Object? _visiblesClave;

  // ---------------------------------------------------------------- permisos

  bool _puede(String accion, [String? almacen]) => _usuario.puede(
      Modulo.inventarioDe(almacen ?? almacenId ?? ''), accion,
      reglaAnterior: false);

  bool get puedeEditar => almacenId != null && _puede(Accion.editar);
  bool get puedeCrear => almacenId != null && _puede(Accion.crear);
  bool get puedeEliminar => almacenId != null && _puede(Accion.eliminar);

  /// La salida directa (sin pedido ni firma) es una acción de Almacén
  /// General sobre lo que tiene en su estante (sección 13 del md).
  /// El filtro "Pedido" (ítems a reponer) es para quien compra o pide: el
  /// Gerente solo mira (ver [Rol.soloInformes]).
  bool get muestraFiltroPedido => !_usuario.soloInformes;

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
    limiteTabla = filasPorTanda;
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
    final otroAlmacen = id != almacenId;
    final resultados =
        await Future.wait([_repo.categoriasTodas(), _repo.existencias(id)]);
    almacenId = id;
    categorias = resultados[0] as List<CategoriaInv>;
    existencias = resultados[1] as List<ExistenciaItem>;
    _relevantes = _calcularRelevantes();
    if (categoriaFiltro != null && !_relevantes.contains(categoriaFiltro)) {
      categoriaFiltro = null;
    }
    if (otroAlmacen) tiposFiltro = {};
    cargando = false;
    error = null;
    notifyListeners();
    if (otroAlmacen && periodoActivo) _cargarPeriodo();
  }

  /// Categorías propias del almacén actual: las únicas donde se pueden dar
  /// de alta ítems nuevos.
  List<CategoriaInv> get categoriasPropias =>
      categorias.where((c) => c.almacenId == almacenId).toList();

  CategoriaInv? _categoriaPorId(int id) {
    _asegurarIndices();
    return _porId[id];
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

  /// La búsqueda se aplica al toque ([visibles] ya la usa), pero la pantalla
  /// se redibuja recién cuando se deja de escribir un momento: redibujar la
  /// tabla a cada letra era lo que hacía sentir lento el buscador.
  void buscar(String texto) {
    busqueda = texto;
    limiteTabla = filasPorTanda;
    _redibujarBusqueda?.cancel();
    _redibujarBusqueda = Timer(const Duration(milliseconds: 200), notifyListeners);
  }

  void filtrarCategoria(int? id) {
    categoriaFiltro = id;
    limiteTabla = filasPorTanda;
    notifyListeners();
  }

  /// Las categorías de primer nivel del almacén actual (para "Filtrar por tipo").
  List<CategoriaInv> get tipos => hijosDe(null);

  void filtrarTipos(Set<int> ids) {
    tiposFiltro = {...ids};
    limiteTabla = filasPorTanda;
    notifyListeners();
  }

  void alternarSoloPedido() {
    soloPedido = !soloPedido;
    limiteTabla = filasPorTanda;
    notifyListeners();
  }

  /// Lo que manda la barra de filtros: el texto se aplica como [buscar]; si
  /// cambiaron las fechas, se traen las entradas/salidas de ese período.
  void filtrar(FiltroLista f) {
    final cambiaronFechas = f.desde != filtro.desde || f.hasta != filtro.hasta;
    filtro = f;
    if (f.texto != busqueda) buscar(f.texto);
    if (cambiaronFechas) {
      limiteTabla = filasPorTanda;
      _cargarPeriodo();
    }
  }

  bool get periodoActivo => filtro.desde != null || filtro.hasta != null;

  Future<void> _cargarPeriodo() async {
    final pedido = ++_pedidoPeriodo;
    errorPeriodo = null;
    if (!periodoActivo || almacenId == null) {
      _periodo = null;
      cargandoPeriodo = false;
      _visiblesMemo = null;
      notifyListeners();
      return;
    }
    cargandoPeriodo = true;
    notifyListeners();
    // Sin Desde: desde el principio; sin Hasta: hasta hoy (incluido).
    final d = filtro.desde ?? DateTime(2000);
    final h0 = filtro.hasta ?? DateTime.now();
    final hasta = DateTime(h0.year, h0.month, h0.day + 1);
    final desde = DateTime(d.year, d.month, d.day);
    try {
      final r = await _repo.movimientosPeriodo(almacenId!, desde, hasta);
      if (pedido != _pedidoPeriodo || _cerrado) return;
      _periodo = r;
    } catch (e) {
      if (pedido != _pedidoPeriodo || _cerrado) return;
      if (kDebugMode) debugPrint('InventarioService: $e');
      _periodo = const {};
      errorPeriodo = 'No se pudieron traer los movimientos de esas fechas. Revisá la conexión.';
    }
    cargandoPeriodo = false;
    _visiblesMemo = null;
    notifyListeners();
  }

  /// Entradas/salidas del ítem en el período elegido (null sin fechas).
  MovimientoPeriodo? movimientoDe(ExistenciaItem e) =>
      periodoActivo ? (_periodo?[e.itemId] ?? const MovimientoPeriodo()) : null;

  /// La lista de ítems aparece al entrar a una categoría, al buscar o al
  /// filtrar (texto, fechas o "Pedido"); en la raíz sin nada de eso se ven
  /// solo las categorías (el reporte, igual, sale con todo el almacén).
  bool get mostrarTabla =>
      categoriaFiltro != null ||
      busqueda.trim().isNotEmpty ||
      soloPedido ||
      periodoActivo ||
      tiposFiltro.isNotEmpty;

  List<CategoriaInv> hijosDe(int? padreId) {
    _asegurarIndices();
    return [
      for (final c in _hijosPorPadre[padreId] ?? const <CategoriaInv>[])
        if (_relevantes.contains(c.id)) c
    ];
  }

  /// Camino desde la raíz hasta [id]: [PET, Tapas, Tapa Short].
  List<CategoriaInv> rutaDe(int id) {
    _asegurarIndices();
    return _rutas[id] ??= () {
      final ruta = <CategoriaInv>[];
      int? actual = id;
      while (actual != null) {
        final c = _porId[actual];
        if (c == null || ruta.contains(c)) break;
        ruta.insert(0, c);
        actual = c.padreId;
      }
      return List<CategoriaInv>.unmodifiable(ruta);
    }();
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
    _asegurarIndices();
    return _resumenes[categoriaId] ??= () {
      final ids = _idsConDescendientes(categoriaId);
      var items = 0, pedidos = 0, criticos = 0;
      for (final e in existencias) {
        if (!ids.contains(e.categoriaId)) continue;
        items++;
        if (necesitaPedido(e)) pedidos++;
        if (situacion(e) == SituacionStock.critico) criticos++;
      }
      return ResumenCategoria(items: items, pedidos: pedidos, criticos: criticos);
    }();
  }

  Set<int> _idsConDescendientes(int id) {
    _asegurarIndices();
    return _descendientes[id] ??= () {
      final ids = {id};
      var pendientes = [id];
      while (pendientes.isNotEmpty) {
        final hijos = [
          for (final p in pendientes)
            for (final c in _hijosPorPadre[p] ?? const <CategoriaInv>[])
              if (ids.add(c.id)) c.id
        ];
        pendientes = hijos;
      }
      return ids;
    }();
  }

  /// Palabras de la búsqueda actual (sin tildes, minúsculas), para exigir
  /// que TODAS aparezcan (en cualquier orden, en detalle o código) — así
  /// "tapa negra" encuentra "Tapa Short Negra" aunque no sea ese el orden.
  List<String> get _palabrasBusqueda =>
      sinTildes(busqueda.trim()).split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();

  /// La búsqueda separada por comas es "esto O aquello": "tapa negra, preforma 28"
  /// trae los dos productos (para sacar un reporte de varios). Dentro de cada
  /// parte, todas sus palabras tienen que aparecer.
  List<List<String>> get _gruposBusqueda => [
        for (final parte in sinTildes(busqueda.trim()).split(','))
          if (parte.trim().isNotEmpty)
            parte.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList()
      ];

  /// Si hay algo escrito en el buscador, se busca en TODO el almacén, no
  /// solo dentro de la categoría abierta: no debería hacer falta saber en
  /// qué categoría está un ítem para poder encontrarlo escribiendo su
  /// nombre. Al borrar la búsqueda se vuelve a ver la categoría de antes.
  bool get buscandoEnTodoElAlmacen => categoriaFiltro != null && _palabrasBusqueda.isNotEmpty;

  /// Ítems que pasan la categoría, la búsqueda y el filtro "Pedido".
  ///
  /// La pantalla lo pide varias veces por dibujado (tabla, contadores, PDF):
  /// se calcula una sola vez por combinación de filtros.
  List<ExistenciaItem> get visibles {
    _asegurarIndices();
    final clave = (busqueda.trim(), categoriaFiltro, soloPedido, periodoActivo,
        identityHashCode(_periodo), Object.hashAllUnordered(tiposFiltro));
    final memo = _visiblesMemo;
    if (memo != null && _visiblesClave == clave) return memo;

    final palabras = _palabrasBusqueda;
    final grupos = _gruposBusqueda;
    final idsTipos = tiposFiltro.isEmpty
        ? null
        : {for (final t in tiposFiltro) ..._idsConDescendientes(t)};
    final ids = (categoriaFiltro != null && palabras.isEmpty)
        ? _idsConDescendientes(categoriaFiltro!)
        : null;
    final resultado = List<ExistenciaItem>.unmodifiable(existencias.where((e) {
      if (ids != null && !ids.contains(e.categoriaId)) return false;
      if (idsTipos != null && !idsTipos.contains(e.categoriaId)) return false;
      if (soloPedido && !necesitaPedido(e)) return false;
      // Con fechas: solo lo que se movió en ese período.
      if (periodoActivo && _periodo != null && !_periodo!.containsKey(e.itemId)) return false;
      if (palabras.isEmpty) return true;
      final texto = _textoDe(e);
      return grupos.any((g) => g.every(texto.contains));
    }));
    _visiblesClave = clave;
    return _visiblesMemo = resultado;
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

  static String textoSituacion(SituacionStock s) {
    switch (s) {
      case SituacionStock.critico:
        return 'Crítico';
      case SituacionStock.bajo:
        return 'Bajo';
      case SituacionStock.optimo:
        return 'Óptimo';
      case SituacionStock.sinDatos:
        return 'Sin consumo';
    }
  }

  /// Reporte PDF/Excel con EXACTAMENTE lo que se ve (almacén, categoría,
  /// búsqueda, fechas y "Pedido"). En la raíz sin filtros: todo el almacén.
  ReporteTabla reporte() {
    final almacen = almacenes.where((a) => a.id == almacenId).firstOrNull?.nombre ?? '';
    final conPeriodo = periodoActivo;
    return ReporteTabla(
      titulo: 'Inventario · $almacen',
      filtros: [
        if (categoriaFiltro != null) 'Categoría: ${textoRuta(categoriaFiltro!)}',
        if (tiposFiltro.isNotEmpty)
          'Tipos: ${[for (final t in tipos) if (tiposFiltro.contains(t.id)) t.nombre].join(", ")}',
        filtro.describir(),
        if (soloPedido) 'Solo ítems a pedir',
      ].join('   ·   '),
      columnas: [
        'Código', 'Detalle', 'Ubicación', 'Stock', 'Unidad', 'Mínimo', 'Días', 'Estado',
        if (conPeriodo) ...['Entradas', 'Salidas'],
      ],
      filas: [
        for (final e in visibles)
          [
            e.codigo, e.detalle, textoRutaRelativa(e.categoriaId), e.cantidadSistema, e.unidad,
            e.stockMinimo, e.diasExistencia, textoSituacion(situacion(e)),
            if (conPeriodo) ...[movimientoDe(e)!.entradas, movimientoDe(e)!.salidas],
          ]
      ],
    );
  }

  /// Marca "Pedido" cuando el stock llegó al mínimo definido para el ítem.
  bool necesitaPedido(ExistenciaItem e) =>
      e.stockMinimo != null && e.cantidadSistema <= e.stockMinimo!;

  // ---------------------------------------------------------------- acciones

  Future<ItemInventario> cargarItem(int id) => _repo.item(id);

  static const maxFotoItemBytes = 5 * 1024 * 1024;

  /// Devuelve null si salió bien, o el mensaje de error. Con [foto] (bytes y
  /// extensión), primero la sube y la deja como foto del ítem.
  Future<String?> guardarItem(ItemInventario item, {(Uint8List, String)? foto}) async {
    final error = _validarItem(item);
    if (error != null) return error;
    final permiso = item.id == null ? puedeCrear : puedeEditar;
    if (!permiso) return 'No tenés permiso para modificar este almacén.';
    if (foto != null) {
      if (!['jpg', 'jpeg', 'png', 'webp'].contains(foto.$2)) return 'La foto debe ser JPG, PNG o WEBP.';
      if (foto.$1.length > maxFotoItemBytes) return 'La foto pesa más de 5 MB.';
      try {
        item = item.conFoto(await _repo.subirFotoItem(foto.$1, foto.$2));
      } catch (e) {
        if (kDebugMode) debugPrint('InventarioService.subirFotoItem: $e');
        return 'No se pudo subir la foto. Revisá la conexión (y que esté corrida la migración v48).';
      }
    }
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

  // ---------------------------------------------------------- importar Excel

  /// Rutas de las categorías propias del almacén (para leer el Excel y para
  /// la hoja "Categorías" de la plantilla), ordenadas.
  Map<int, String> get _rutasPropias {
    final m = {for (final c in categoriasPropias) c.id: textoRuta(c.id)};
    return Map.fromEntries(m.entries.toList()..sort((a, b) => a.value.compareTo(b.value)));
  }

  LecturaExcel leerExcel(Uint8List bytes) => leerExcelInventario(
        bytes,
        ContextoExcel(
          rutas: _rutasPropias,
          porCodigo: {for (final e in existencias) e.codigo.toUpperCase(): e.itemId},
          porDetalle: {
            for (final e in existencias)
              sinTildes(e.detalle).replaceAll(RegExp(r'[^a-z0-9]'), ''): e.itemId
          },
        ),
      );

  /// Nombre del archivo de la plantilla (con la categoría abierta, si hay).
  String get nombrePlantilla => categoriaFiltro == null
      ? 'plantilla_inventario'
      : 'plantilla_${sinTildes(_categoriaPorId(categoriaFiltro!)?.nombre ?? 'categoria').replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

  /// Plantilla según dónde se está parado: dentro de una categoría (ej.
  /// Termocontraíbles) trae solo sus categorías y las columnas que usan sus
  /// ítems; en la raíz, la general con todo. De ejemplo, el primer ítem de la
  /// lista. Sin conexión, sale igual pero con todas las columnas y sin ejemplo.
  Future<Uint8List> plantillaExcel() async {
    final almacen = almacenes.where((a) => a.id == almacenId).firstOrNull?.nombre ?? 'Almacén';
    final cat = categoriaFiltro;
    final ids = cat == null ? null : _idsConDescendientes(cat);
    final rutas = {
      for (final e in _rutasPropias.entries)
        if (ids == null || ids.contains(e.key)) e.key: e.value
    };
    final enLista = [
      for (final e in (visibles.isNotEmpty ? visibles : existencias))
        if (ids == null || ids.contains(e.categoriaId)) e
    ];
    List<ItemInventario> fichas = const [];
    try {
      // Una categoría: todos sus ítems (para saber qué columnas usan); la
      // general: solo el del ejemplo.
      fichas = await _repo.itemsPorId(
          [for (final e in (cat == null ? enLista.take(1) : enLista.take(500))) e.itemId]);
    } catch (_) {}
    final primero = enLista.isEmpty
        ? null
        : fichas.where((f) => f.id == enLista.first.itemId).firstOrNull;
    return plantillaExcelInventario(
      almacen,
      rutas.values.toList(),
      columnas: cat == null || fichas.isEmpty ? null : columnasUsadas(fichas),
      ejemplo: primero == null ? null : (primero, textoRuta(primero.categoriaId)),
      categoria: cat == null ? null : _categoriaPorId(cat)?.nombre,
      extras: ({for (final f in fichas) ...f.otrosDatos.keys}.toList()..sort()),
    );
  }

  /// Crea los ítems nuevos (uno por uno, avisando el avance) y, con
  /// [cargarStock], registra la columna Stock como conteo físico de todos (los
  /// nuevos y los que ya existían) en un solo envío. Devuelve el resumen.
  Future<({int creados, int contados, List<String> errores})> importarExcel(
    LecturaExcel lectura, {
    bool cargarStock = false,
    void Function(int hechos, int total)? progreso,
  }) async {
    if (!puedeCrear) return (creados: 0, contados: 0, errores: ['No tenés permiso para crear ítems en este almacén.']);
    final errores = <String>[];
    final conteos = <ConteoNuevo>[];
    var creados = 0;
    final nuevos = lectura.nuevos;
    for (var i = 0; i < nuevos.length; i++) {
      final f = nuevos[i];
      final error = _validarItem(f.nuevo!);
      if (error != null) {
        errores.add('Fila ${f.fila} (${f.detalle}): $error');
      } else {
        try {
          final id = await _repo.crearItem(f.nuevo!);
          creados++;
          if (cargarStock && f.stock != null && id != null) {
            conteos.add(ConteoNuevo(itemId: id, almacenId: almacenId!, cantidadReal: f.stock!, observaciones: 'Importado de Excel'));
          }
        } catch (e) {
          errores.add('Fila ${f.fila} (${f.detalle}): ${_mensaje(e, 'no se pudo crear')}');
        }
      }
      progreso?.call(i + 1, nuevos.length);
    }
    if (cargarStock && puedeEditar) {
      for (final f in lectura.existentes) {
        if (f.stock != null) {
          conteos.add(ConteoNuevo(itemId: f.existenteId!, almacenId: almacenId!, cantidadReal: f.stock!, observaciones: 'Importado de Excel'));
        }
      }
    }
    var contados = 0;
    if (conteos.isNotEmpty) {
      try {
        await _repo.registrarConteos(conteos);
        contados = conteos.length;
      } catch (e) {
        errores.add('El stock no se cargó: ${_mensaje(e, 'error al registrar los conteos')}');
      }
    }
    await recargar();
    return (creados: creados, contados: contados, errores: errores);
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

  /// Ficha de UN ítem en PDF (acción de la tabla): sus datos, características,
  /// otros datos y los últimos 100 movimientos en este almacén.
  Future<Uint8List> fichaPdf(ExistenciaItem e) async {
    final r = await Future.wait([_repo.item(e.itemId), movimientosDe(e)]);
    final item = r[0] as ItemInventario;
    final movs = r[1] as List<MovimientoInv>;
    final sit = situacion(e);
    String? n(Object? v, [String? u]) =>
        v == null ? null : '${v is num ? fmtNum(v) : v}${u == null ? '' : ' $u'}';
    return ComprobantePdf.generar(
      titulo: 'Ficha de ítem',
      subtitulo: '${e.codigo} · ${almacenes.where((a) => a.id == e.almacenId).firstOrNull?.nombre ?? ''}',
      estado: textoSituacion(sit),
      colorEstado: switch (sit) {
        SituacionStock.critico => 0xFFDC2626,
        SituacionStock.bajo => 0xFFD97706,
        SituacionStock.optimo => 0xFF16A34A,
        SituacionStock.sinDatos => 0xFF6B7280,
      },
      secciones: [
        (null, [
          ('Detalle', e.detalle),
          ('Código', e.codigo),
          ('Ubicación', textoRuta(e.categoriaId)),
          ('Unidad', e.unidad),
        ]),
        ('Stock', [
          ('En el sistema', n(e.cantidadSistema, e.unidad)),
          ('Último conteo físico', n(e.cantidadReal, e.unidad)),
          ('Stock mínimo', n(e.stockMinimo, e.unidad)),
          ('Consumo diario', n(e.consumoDiario, e.unidad)),
          ('Días de existencia', e.diasExistencia == null ? null : fmtNum(e.diasExistencia, decimales: 1)),
          ('Necesita pedido', necesitaPedido(e) ? 'Sí' : null),
        ]),
        ('Compra y empaque', [
          ('Se compra en', item.unidadCompra == null
              ? null
              : '${item.unidadCompra} de ${n(item.factorCompra, e.unidad) ?? '—'}'),
          ('Unidades por caja', n(item.unidadesPorCaja)),
        ]),
        ('Características', [
          ('Color', n(item.atributos['color'])),
          ('Formato', n(item.atributos['formato'])),
          ('Peso', n(item.atributos['peso_g'], 'g')),
          ('Ancho', n(item.atributos['ancho_mm'], 'mm')),
          ('Micronaje', n(item.atributos['micronaje'])),
        ]),
        ('Otros datos', [for (final o in item.otrosDatos.entries) (o.key, n(o.value))]),
      ],
      tablas: [
        TablaComprobante(
          titulo: 'Últimos movimientos',
          encabezados: const ['Fecha', 'Tipo', 'Cantidad', 'Lote', 'Motivo', 'Usuario'],
          filas: [
            for (final m in movs)
              [
                fmtFechaHora(m.fecha),
                '${m.tipo[0].toUpperCase()}${m.tipo.substring(1)}${m.revertido ? ' (revertido)' : ''}',
                '${m.cantidad > 0 ? '+' : ''}${fmtNum(m.cantidad)} ${e.unidad}',
                m.nLote ?? '',
                m.motivo ?? '',
                m.usuarioNombre ?? '',
              ]
          ],
        ),
      ],
    );
  }

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
