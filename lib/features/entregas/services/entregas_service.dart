import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/entregas_modelos.dart';
import '../repositories/entregas_repository.dart';

/// Pestañas de la bandeja de pedidos.
enum BandejaPedidos {
  pendientes('Por entregar', [EstadoPedido.pendiente]),
  porConfirmar('Por confirmar', [EstadoPedido.entregado]),
  observados('Con observaciones', [EstadoPedido.observado]),
  cerrados('Cerrados', [EstadoPedido.cerrado, EstadoPedido.anulado]);

  final String etiqueta;
  final List<EstadoPedido> estados;
  const BandejaPedidos(this.etiqueta, this.estados);
}

/// Reglas de pedidos, entregas y conformidad. Espeja las validaciones del
/// servidor para avisar rápido, pero quien decide es el servidor (RLS y
/// funciones). No conoce widgets.
class EntregasService extends ChangeNotifier {
  EntregasService(this._repo, this._usuario);

  static const almacenOrigen = 'general';
  static const maxLineas = 60;
  static const _tolerancia = 1e-9;

  final EntregasRepository _repo;
  final Usuario _usuario;

  List<Pedido> pedidos = [];
  BandejaPedidos bandeja = BandejaPedidos.pendientes;
  bool cargando = true;
  String? error;

  List<ItemPedible>? _items;

  // ---------------------------------------------------------------- permisos

  bool _puede(String modulo, String accion) =>
      _usuario.puede(modulo, accion, reglaAnterior: false);

  bool get puedeVer => _puede(Modulo.entregas, Accion.ver);

  /// Almacén: entrega, y arma pedidos para cualquier área.
  bool get esAlmacen => _puede(Modulo.entregas, Accion.crear);

  bool get puedePedir => _puede(Modulo.solicitudes, Accion.crear);

  /// Área a la que pertenece quien está usando el sistema (null si no recibe).
  String? get areaPropia => AreaPedido.deRol(_usuario.rol);

  bool get puedeCrearPedido => puedePedir && (esAlmacen || areaPropia != null);

  bool puedeEntregar(Pedido p) => esAlmacen && p.estado == EstadoPedido.pendiente;

  bool puedeConfirmar(Pedido p) =>
      p.estado == EstadoPedido.entregado &&
      _puede(Modulo.entregas, Accion.editar) &&
      (areaPropia == p.areaDestino || p.solicitanteId == _usuario.id);

  bool puedeResolver(Pedido p) => esAlmacen && p.estado == EstadoPedido.observado;

  bool puedeAnular(Pedido p) =>
      p.estado == EstadoPedido.pendiente && (p.solicitanteId == _usuario.id || esAlmacen);

  /// Almacén puede devolver lo que sobró de una línea ya entregada (lo que
  /// pidió de más un área). No aplica a pedidos pendientes o anulados: ahí
  /// no se entregó nada todavía.
  bool puedeDevolver(Pedido p, LineaPedido l) =>
      esAlmacen &&
      p.estado != EstadoPedido.pendiente &&
      p.estado != EstadoPedido.anulado &&
      l.disponibleParaDevolver > _tolerancia;

  // ------------------------------------------------------------------- carga

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    notifyListeners();
    if (!puedeVer) {
      cargando = false;
      notifyListeners();
      return;
    }
    await recargar();
  }

  Future<void> recargar() async {
    try {
      pedidos = await _repo.pedidos();
      error = null;
      _items = null; // el stock disponible cambia con cada entrega
    } catch (e) {
      error = 'No se pudieron cargar los pedidos. Revisá la conexión o que la '
          'migración v21 esté ejecutada.';
      if (kDebugMode) debugPrint('EntregasService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  void elegirBandeja(BandejaPedidos b) {
    bandeja = b;
    notifyListeners();
  }

  List<Pedido> get visibles =>
      pedidos.where((p) => bandeja.estados.contains(p.estado)).toList();

  int cantidadEn(BandejaPedidos b) =>
      pedidos.where((p) => b.estados.contains(p.estado)).length;

  /// Pedidos que esperan algo de esta persona (para resaltarlos).
  int get pendientesDeMiAccion => pedidos.where((p) {
        return puedeEntregar(p) || puedeConfirmar(p) || puedeResolver(p);
      }).length;

  Future<List<ItemPedible>> itemsPedibles() async =>
      _items ??= await _repo.itemsPedibles(almacenOrigen);

  // ---------------------------------------------------------------- acciones

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> crearPedido({
    String? area,
    String? motivo,
    required List<LineaNueva> lineas,
    bool entregarAhora = false,
  }) async {
    if (!puedeCrearPedido) return 'No tenés permiso para hacer pedidos.';
    if (entregarAhora && !esAlmacen) return 'Solo Almacén puede entregar.';

    final destino = esAlmacen ? area : areaPropia;
    if (destino == null || !AreaPedido.todas.contains(destino)) {
      return 'Elegí el área que recibe los materiales.';
    }
    if (lineas.isEmpty) return 'Agregá al menos un ítem.';
    if (lineas.length > maxLineas) return 'Un pedido puede tener hasta $maxLineas ítems.';
    if (lineas.map((l) => l.itemId).toSet().length != lineas.length) {
      return 'Hay un ítem repetido: sumá las cantidades en una sola línea.';
    }
    if (lineas.any((l) => l.cantidad.isNaN || l.cantidad <= 0)) {
      return 'Cada ítem necesita una cantidad mayor a cero.';
    }
    final motivoLimpio = motivo?.trim();
    if (motivoLimpio != null && motivoLimpio.length > 300) return 'El motivo es demasiado largo.';

    if (entregarAhora) {
      final items = {for (final i in await itemsPedibles()) i.id: i};
      for (final l in lineas) {
        final item = items[l.itemId];
        if (item == null) return 'Uno de los ítems no está en el Almacén General.';
        if (l.cantidad > item.disponible + _tolerancia) {
          return 'No alcanza "${item.detalle}": hay ${_n(item.disponible)} ${item.unidad}.';
        }
      }
    }

    return _ejecutar(() async {
      await _repo.crearPedido(
        area: esAlmacen ? destino : null,
        motivo: (motivoLimpio == null || motivoLimpio.isEmpty) ? null : motivoLimpio,
        lineas: lineas,
        entregar: entregarAhora,
      );
    });
  }

  /// [cantidades] permite entregar menos de lo pedido (por id de línea).
  Future<String?> entregar(Pedido p, {Map<int, double>? cantidades}) async {
    if (!puedeEntregar(p)) return 'No podés entregar este pedido.';
    if (cantidades != null) {
      final porId = {for (final l in p.lineas) l.id: l};
      for (final e in cantidades.entries) {
        final linea = porId[e.key];
        if (linea == null) return 'Línea de pedido desconocida.';
        if (e.value.isNaN || e.value < 0) return 'Las cantidades no pueden ser negativas.';
        if (e.value > linea.cantidadPedida + _tolerancia) {
          return 'No se puede entregar más de lo pedido de "${linea.detalle}".';
        }
      }
      if (cantidades.values.every((v) => v == 0)) {
        return 'No hay nada para entregar: si no se entrega, anulá el pedido.';
      }
    }
    return _ejecutar(() => _repo.entregar(p.id, cantidades: cantidades));
  }

  Future<String?> confirmar(
    Pedido p,
    List<ConfirmacionLinea> lineas, {
    String? nota,
  }) async {
    if (!puedeConfirmar(p)) return 'No podés confirmar esta entrega.';
    final porId = {for (final l in p.lineas) l.id: l};
    if (lineas.length != p.lineas.length || lineas.any((l) => !porId.containsKey(l.lineaId))) {
      return 'Falta revisar alguno de los ítems.';
    }
    for (final c in lineas) {
      final l = porId[c.lineaId]!;
      final entregada = l.cantidadEntregada ?? 0;
      if (c.cantidadRecibida.isNaN || c.cantidadRecibida < 0) {
        return 'La cantidad recibida de "${l.detalle}" no puede ser negativa.';
      }
      if (c.cantidadRecibida > entregada + _tolerancia) {
        return 'No podés haber recibido más de lo entregado de "${l.detalle}".';
      }
      final difiere = (c.cantidadRecibida - entregada).abs() > _tolerancia;
      final obs = c.observacion?.trim() ?? '';
      if ((!c.recibidoOk || difiere) && obs.isEmpty) {
        return 'Explicá con una observación qué pasó con "${l.detalle}".';
      }
      if (obs.length > 300) return 'Una observación es demasiado larga.';
    }
    if ((nota?.trim().length ?? 0) > 300) return 'La nota es demasiado larga.';
    return _ejecutar(() => _repo.confirmar(p.id, lineas, nota: nota?.trim()));
  }

  Future<String?> resolver(Pedido p, String resolucion) async {
    if (!puedeResolver(p)) return 'No podés resolver este pedido.';
    final t = resolucion.trim();
    if (t.length < 3 || t.length > 300) return 'Escribí cómo se resolvió (3 a 300 caracteres).';
    return _ejecutar(() => _repo.resolver(p.id, t));
  }

  Future<String?> anular(Pedido p, String motivo) async {
    if (!puedeAnular(p)) return 'No podés anular este pedido.';
    final t = motivo.trim();
    if (t.length < 3 || t.length > 300) return 'Escribí el motivo (3 a 300 caracteres).';
    return _ejecutar(() => _repo.anular(p.id, t));
  }

  Future<String?> registrarDevolucion(Pedido p, LineaPedido l, double? cantidad, String? motivo) async {
    if (!puedeDevolver(p, l)) return 'No podés registrar una devolución de esta línea.';
    if (cantidad == null || cantidad.isNaN || cantidad <= 0) {
      return 'La cantidad a devolver debe ser mayor a cero.';
    }
    if (cantidad > l.disponibleParaDevolver + _tolerancia) {
      return 'No se puede devolver más de lo entregado: quedan '
          '${_n(l.disponibleParaDevolver)} ${l.unidad} disponibles.';
    }
    if ((motivo?.length ?? 0) > 300) return 'El motivo es demasiado largo.';
    return _ejecutar(() => _repo.registrarDevolucion(l.id, cantidad, motivo: motivo?.trim()));
  }

  // ------------------------------------------------------------------ ayudas

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocio catch (e) {
      await recargar(); // por si otro cambió el estado del pedido
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('EntregasService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);
}
