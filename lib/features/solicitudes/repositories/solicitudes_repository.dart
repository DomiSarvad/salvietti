import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/solicitud.dart';

/// Acceso a datos de Solicitudes a Gerencia. Las escrituras pasan por
/// funciones del servidor (validan permisos y son atómicas); acá solo se
/// llaman.
abstract class SolicitudesRepository {
  Future<List<Solicitud>> solicitudes({int limite = 300});
  Future<List<ItemReferencia>> items({String? busqueda});
  Future<int> crear(SolicitudNueva s);
  Future<void> resolver(int id, {required bool aprobar, String? respuesta});
}

class SupabaseSolicitudesRepository implements SolicitudesRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<Solicitud>> solicitudes({int limite = 300}) async {
    final filas = await _db
        .from('solicitudes_gerencia')
        .select('*, inv_items(detalle, unidad)')
        .order('fecha', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Solicitud.fromMap(f)];
  }

  @override
  Future<List<ItemReferencia>> items({String? busqueda}) async {
    var query = _db.from('inv_items').select('id, codigo, detalle, unidad').eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('detalle', '%${busqueda.trim()}%');
    }
    final filas = await query.order('detalle').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemReferencia.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioSolicitud(e.message);
      rethrow;
    }
  }

  @override
  Future<int> crear(SolicitudNueva s) async {
    final id = await _rpc<dynamic>('solicitud_crear', {
      'p_tipo': s.tipo,
      'p_asunto': s.asunto,
      'p_detalle': s.detalle,
      'p_item_id': s.itemId,
      'p_cantidad': s.cantidadSugerida,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> resolver(int id, {required bool aprobar, String? respuesta}) async {
    await _rpc<dynamic>('solicitud_resolver', {
      'p_id': id,
      'p_aprobar': aprobar,
      'p_respuesta': respuesta,
    });
  }
}
