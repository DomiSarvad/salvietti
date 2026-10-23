import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/realtime.dart';
import '../models/compras_modelos.dart';

export '../../../shared/realtime.dart' show Suscripcion, SuscripcionNula;

/// Acceso a datos de Pedidos de compra. Las escrituras pasan por funciones
/// del servidor (v43), que validan permisos y estado.
abstract class ComprasRepository {
  Future<List<PedidoCompra>> pedidos({int limite = 200});
  Future<List<ItemCompra>> items();
  Future<int> crear(String? motivo, List<LineaNueva> lineas);
  Future<void> resolver(int id, {required bool aprobar, String? respuesta});
  Future<void> anular(int id);

  /// Avisa cuando cambia cualquier pedido (de cualquier persona).
  Suscripcion escucharCambios(void Function() onCambio);
}

class SupabaseComprasRepository implements ComprasRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<PedidoCompra>> pedidos({int limite = 200}) async {
    final filas = await _db
        .from('compras_pedidos')
        .select('*, compras_pedido_lineas(item_id, cantidad, nota, inv_items(codigo, detalle, unidad))')
        .order('fecha', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) PedidoCompra.fromMap(f)];
  }

  @override
  Future<List<ItemCompra>> items() async {
    final filas = await SupabaseService.todasLasFilas((d, h) => _db
        .from('inv_items')
        .select('id, codigo, detalle, unidad')
        .eq('activo', true)
        .order('detalle')
        .range(d, h));
    return [for (final f in filas) ItemCompra.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioCompra(e.message);
      rethrow;
    }
  }

  @override
  Future<int> crear(String? motivo, List<LineaNueva> lineas) async {
    final id = await _rpc<dynamic>('compras_crear_pedido', {
      'p_motivo': motivo,
      'p_lineas': [
        for (final l in lineas) {'item_id': l.item.id, 'cantidad': l.cantidad, 'nota': l.nota}
      ],
    });
    return (id as num).toInt();
  }

  @override
  Future<void> resolver(int id, {required bool aprobar, String? respuesta}) => _rpc<dynamic>(
      'compras_resolver', {'p_id': id, 'p_aprobar': aprobar, 'p_respuesta': respuesta});

  @override
  Future<void> anular(int id) => _rpc<dynamic>('compras_anular', {'p_id': id});

  @override
  Suscripcion escucharCambios(void Function() onCambio) =>
      escucharTablas('compras_cambios', const ['compras_pedidos'], onCambio);
}
