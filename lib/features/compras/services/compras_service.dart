import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../shared/busqueda_local.dart';
import '../models/compras_modelos.dart';
import '../repositories/compras_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';
import '../../../utils/formatters.dart';

/// Reglas de los pedidos de compra: Almacén los arma (varias líneas), el
/// Gerente los aprueba o rechaza enteros, y quien lo hizo puede anularlo
/// mientras esté pendiente. No conoce widgets.
class ComprasService extends ChangeNotifier {
  ComprasService(this._repo, this._usuario);

  final ComprasRepository _repo;
  final Usuario _usuario;

  List<PedidoCompra> pedidos = [];
  bool cargando = true;
  String? error;

  /// Filtro de la pantalla: null = todos.
  EstadoCompra? filtroEstado;

  bool _puede(String accion) => _usuario.puede(Modulo.compras, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeAprobar => _puede(Accion.aprobar);

  static const maxLineas = 100;

  Suscripcion? _suscripcion;
  Timer? _recargaPendiente;
  bool _cerrado = false;

  @override
  void dispose() {
    _cerrado = true;
    _suscripcion?.cancelar();
    _recargaPendiente?.cancel();
    super.dispose();
  }

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    filtroEstado = puedeAprobar ? EstadoCompra.pendiente : null;
    notifyListeners();
    if (!puedeVer) {
      cargando = false;
      notifyListeners();
      return;
    }
    await _cargar();
    // Tiempo real: el Gerente ve llegar los pedidos; Almacén ve la respuesta.
    _suscripcion ??= _repo.escucharCambios(() {
      _recargaPendiente?.cancel();
      _recargaPendiente = Timer(const Duration(milliseconds: 400), () => _cargar(silencioso: true));
    });
  }

  Future<void> recargar() => _cargar();

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      pedidos = await _repo.pedidos();
      error = null;
    } catch (e) {
      if (!silencioso) {
        error = 'No se pudieron cargar los pedidos de compra. Revisá la conexión o que '
            'la migración v43 esté ejecutada.';
      }
      if (kDebugMode) debugPrint('ComprasService: $e');
    }
    if (_cerrado) return;
    cargando = false;
    notifyListeners();
  }

  void filtrarEstado(EstadoCompra? estado) {
    filtroEstado = estado;
    notifyListeners();
  }

  List<PedidoCompra> get visibles =>
      filtroEstado == null ? pedidos : pedidos.where((p) => p.estado == filtroEstado).toList();

  int get pendientes => pedidos.where((p) => p.estado == EstadoCompra.pendiente).length;

  bool puedeAnular(PedidoCompra p) =>
      p.estado == EstadoCompra.pendiente && p.solicitanteId == _usuario.id;

  // Catálogo para elegir ítems: una consulta, se busca en memoria.
  late final _catItems = CatalogoLocal<ItemCompra>(_repo.items, (i) => '${i.codigo} ${i.detalle}');
  Future<List<ItemCompra>> buscarItems(String texto) => _catItems.buscar(texto);
  void precargarItems() => _catItems.precargar();

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> crear(String? motivo, List<LineaNueva> lineas) async {
    if (!puedeCrear) return 'No tenés permiso para hacer pedidos de compra.';
    if (lineas.isEmpty) return 'Agregá al menos un ítem.';
    if (lineas.length > maxLineas) return 'Máximo $maxLineas ítems por pedido.';
    final ids = <int>{};
    for (final l in lineas) {
      if (l.cantidad <= 0) return 'La cantidad de "${l.item.detalle}" tiene que ser mayor a cero.';
      if (!ids.add(l.item.id)) return '"${l.item.detalle}" está dos veces: juntá las cantidades.';
      if ((l.nota?.length ?? 0) > 200) return 'La nota de "${l.item.detalle}" es demasiado larga.';
    }
    final m = motivo?.trim();
    if ((m?.length ?? 0) > 500) return 'El motivo es demasiado largo.';
    return _ejecutar(() => _repo.crear((m == null || m.isEmpty) ? null : m, [
          for (final l in lineas)
            LineaNueva(
              item: l.item,
              cantidad: l.cantidad,
              nota: (l.nota?.trim().isEmpty ?? true) ? null : l.nota!.trim(),
            )
        ]));
  }

  Future<String?> aprobar(PedidoCompra p, {String? respuesta}) => _resolver(p, true, respuesta);

  Future<String?> rechazar(PedidoCompra p, String respuesta) {
    if (respuesta.trim().isEmpty) return Future.value('Explicá el motivo del rechazo.');
    return _resolver(p, false, respuesta);
  }

  Future<String?> _resolver(PedidoCompra p, bool aprobar, String? respuesta) async {
    if (!puedeAprobar) return 'No tenés permiso para aprobar pedidos de compra.';
    if (p.estado != EstadoCompra.pendiente) return 'Este pedido ya fue resuelto.';
    if ((respuesta?.length ?? 0) > 500) return 'La respuesta es demasiado larga.';
    final r = respuesta?.trim();
    return _ejecutar(() =>
        _repo.resolver(p.id, aprobar: aprobar, respuesta: (r == null || r.isEmpty) ? null : r));
  }

  Future<String?> anular(PedidoCompra p) async {
    if (!puedeAnular(p)) return 'Solo quien hizo el pedido lo puede anular, y mientras esté pendiente.';
    return _ejecutar(() => _repo.anular(p.id));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await _cargar(silencioso: true);
      return null;
    } on ErrorNegocioCompra catch (e) {
      await _cargar(silencioso: true);
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('ComprasService: $e');
      return 'No se pudo completar la operación. Revisá la conexión.';
    }
  }

  // ------------------------------------------------- buscador y reporte

  /// Filtro del buscador (texto + Desde/Hasta): define qué se ve en la lista y
  /// qué sale en el reporte PDF/Excel ("lo que ves es lo que se imprime").
  FiltroLista filtro = const FiltroLista();

  void filtrar(FiltroLista f) {
    filtro = f;
    notifyListeners();
  }

  List<PedidoCompra> get visiblesFiltrados => filtro.aplicar(visibles,
      texto: (x) => <String?>[x.solicitanteNombre, x.motivo, x.respuesta, x.estado.etiqueta, '#${x.id}', ...x.lineas.map((l) => '${l.codigo} ${l.detalle}')].whereType<String>().join(' '),
      fecha: (x) => x.fecha);

  ReporteTabla reporte() => ReporteTabla(
        titulo: 'Pedidos de compra',
        filtros: filtro.describir(),
        columnas: const ['N°', 'Fecha', 'Estado', 'Solicitante', 'Ítems', 'Detalle', 'Resuelto por', 'Respuesta'],
        filas: [
          for (final x in visiblesFiltrados) [x.id, x.fecha, x.estado.etiqueta, x.solicitanteNombre, x.lineas.length, x.lineas.map((l) => '${l.detalle} (${fmtNum(l.cantidad)} ${l.unidad})').join('; '), x.resueltoPorNombre, x.respuesta]
        ],
      );
}
