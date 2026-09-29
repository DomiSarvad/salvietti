import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/entregas_modelos.dart';

/// Acceso a datos de pedidos y entregas. Las escrituras pasan por funciones
/// del servidor (que validan permisos y son atómicas); acá solo se llaman.
abstract class EntregasRepository {
  Future<List<Pedido>> pedidos({int limite = 200});
  Future<List<ItemPedible>> itemsPedibles(String almacenOrigen);
  Future<int> crearPedido({
    String? area,
    String? motivo,
    required List<LineaNueva> lineas,
    bool entregar = false,
  });
  Future<void> entregar(int pedidoId, {Map<int, double>? cantidades});
  Future<void> confirmar(int pedidoId, List<ConfirmacionLinea> lineas, {String? nota});
  Future<void> resolver(int pedidoId, String resolucion);
  Future<void> anular(int pedidoId, String motivo);

  /// Devuelve a Almacén lo que sobró de una línea ya entregada.
  Future<void> registrarDevolucion(int lineaId, double cantidad, {String? motivo});
}

class SupabaseEntregasRepository implements EntregasRepository {
  SupabaseClient get _db => SupabaseService.client;

  static const _seleccion =
      '*, inv_pedido_lineas(*, inv_items(codigo, detalle, unidad), '
      'inv_entrega_lotes(n_lote, fecha_vencimiento, cantidad), '
      'inv_devoluciones(cantidad))';

  @override
  Future<List<Pedido>> pedidos({int limite = 200}) async {
    final filas = await _db
        .from('inv_pedidos')
        .select(_seleccion)
        .order('id', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Pedido.fromMap(f)];
  }

  @override
  Future<List<ItemPedible>> itemsPedibles(String almacenOrigen) async {
    final filas = await _db
        .from('inv_existencia')
        .select('item_id, codigo, detalle, unidad, cantidad_sistema')
        .eq('almacen_id', almacenOrigen)
        .order('detalle')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemPedible.fromMap(f)];
  }

  /// Las funciones del servidor avisan con `raise exception` (código P0001):
  /// ese mensaje ya está escrito para la persona.
  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocio(e.message);
      rethrow;
    }
  }

  @override
  Future<int> crearPedido({
    String? area,
    String? motivo,
    required List<LineaNueva> lineas,
    bool entregar = false,
  }) async {
    final id = await _rpc<dynamic>('inv_crear_pedido', {
      'p_area': area,
      'p_motivo': motivo,
      'p_lineas': [for (final l in lineas) l.toMap()],
      'p_entregar': entregar,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> entregar(int pedidoId, {Map<int, double>? cantidades}) async {
    await _rpc<dynamic>('inv_entregar_pedido', {
      'p_pedido': pedidoId,
      'p_lineas': cantidades == null
          ? null
          : [
              for (final e in cantidades.entries) {'linea_id': e.key, 'cantidad': e.value}
            ],
    });
  }

  @override
  Future<void> confirmar(int pedidoId, List<ConfirmacionLinea> lineas, {String? nota}) async {
    await _rpc<dynamic>('inv_confirmar_entrega', {
      'p_pedido': pedidoId,
      'p_lineas': [for (final l in lineas) l.toMap()],
      'p_nota': nota,
    });
  }

  @override
  Future<void> resolver(int pedidoId, String resolucion) async {
    await _rpc<dynamic>(
        'inv_resolver_observacion', {'p_pedido': pedidoId, 'p_resolucion': resolucion});
  }

  @override
  Future<void> anular(int pedidoId, String motivo) async {
    await _rpc<dynamic>('inv_anular_pedido', {'p_pedido': pedidoId, 'p_motivo': motivo});
  }

  @override
  Future<void> registrarDevolucion(int lineaId, double cantidad, {String? motivo}) async {
    await _rpc<dynamic>('inv_registrar_devolucion',
        {'p_linea_id': lineaId, 'p_cantidad': cantidad, 'p_motivo': motivo});
  }
}
