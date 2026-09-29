import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/mermas_modelos.dart';

/// Acceso a datos de Mermas. Las escrituras pasan por una función del
/// servidor (valida permiso por área, causas válidas y cantidades).
abstract class MermasRepository {
  Future<List<Sabor>> sabores();
  Future<List<Presentacion>> presentaciones();
  Future<List<EventoMerma>> consolidado();

  Future<int> registrar({
    required String area,
    required int saborId,
    required List<MapEntry<String, double>> causas,
    int? presentacionId,
    double? cantidadProducida,
    String? motivo,
  });
}

class SupabaseMermasRepository implements MermasRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<Sabor>> sabores() async {
    final filas = await _db
        .from('sabores')
        .select('id, nombre')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Sabor.fromMap(f)];
  }

  @override
  Future<List<Presentacion>> presentaciones() async {
    final filas = await _db
        .from('presentaciones')
        .select('id, nombre')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Presentacion.fromMap(f)];
  }

  @override
  Future<List<EventoMerma>> consolidado() async {
    final filas = await _db
        .from('mermas_consolidado')
        .select()
        .order('fecha', ascending: false)
        .limit(300)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) EventoMerma.fromMap(f)];
  }

  @override
  Future<int> registrar({
    required String area,
    required int saborId,
    required List<MapEntry<String, double>> causas,
    int? presentacionId,
    double? cantidadProducida,
    String? motivo,
  }) async {
    try {
      final id = await _db.rpc('mermas_registrar', params: {
        'p_area': area,
        'p_sabor_id': saborId,
        'p_causas': [for (final c in causas) {'causa': c.key, 'cantidad': c.value}],
        'p_presentacion_id': presentacionId,
        'p_cantidad_producida': cantidadProducida,
        'p_motivo': motivo,
      }).timeout(SupabaseService.timeoutRed);
      return (id as num).toInt();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioMermas(e.message);
      rethrow;
    }
  }
}
