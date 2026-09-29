import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/soda_modelos.dart';

/// Acceso a datos de Soda Cáustica. La entrega pasa por una función del
/// servidor (descuenta el almacén propio por lote, como un pedido).
abstract class SodaRepository {
  Future<List<ItemInventario>> items({String? busqueda});
  Future<List<EntregaSoda>> entregas({int limite = 200});

  Future<int> registrarEntrega({
    required int itemId,
    required double cantidad,
    required String entregadoA,
    String? areaRecibe,
    String? motivo,
  });
}

class SupabaseSodaRepository implements SodaRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<ItemInventario>> items({String? busqueda}) async {
    var query = _db.from('inv_items').select('id, codigo, detalle, unidad').eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('detalle', '%${busqueda.trim()}%');
    }
    final filas = await query.order('detalle').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemInventario.fromMap(f)];
  }

  @override
  Future<List<EntregaSoda>> entregas({int limite = 200}) async {
    final filas = await _db
        .from('soda_entregas_detalle')
        .select()
        .order('fecha_hora', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) EntregaSoda.fromMap(f)];
  }

  @override
  Future<int> registrarEntrega({
    required int itemId,
    required double cantidad,
    required String entregadoA,
    String? areaRecibe,
    String? motivo,
  }) async {
    try {
      final id = await _db.rpc('soda_registrar_entrega', params: {
        'p_item_id': itemId,
        'p_cantidad': cantidad,
        'p_entregado_a': entregadoA,
        'p_area_recibe': areaRecibe,
        'p_motivo': motivo,
      }).timeout(SupabaseService.timeoutRed);
      return (id as num).toInt();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioSoda(e.message);
      rethrow;
    }
  }
}
