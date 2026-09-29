import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/calidad_modelos.dart';

/// Acceso a datos de Control de Calidad. Las escrituras pasan por
/// funciones del servidor (validan permisos y son atómicas).
abstract class CalidadRepository {
  Future<List<PreparadoPendiente>> pendientes();
  Future<List<AnalisisCalidad>> analisis({int limite = 200});

  Future<int> registrarAnalisis(NuevoAnalisis a);
  Future<void> actualizarAnalisis(int id, {String? accionTomada, String? observaciones});
}

class SupabaseCalidadRepository implements CalidadRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<PreparadoPendiente>> pendientes() async {
    final filas = await _db
        .from('calidad_pendientes')
        .select()
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) PreparadoPendiente.fromMap(f)];
  }

  @override
  Future<List<AnalisisCalidad>> analisis({int limite = 200}) async {
    final filas = await _db
        .from('calidad_analisis')
        .select('*, jarabes_preparados(n_lote, sabores(nombre))')
        .order('fecha', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AnalisisCalidad.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioCalidad(e.message);
      rethrow;
    }
  }

  @override
  Future<int> registrarAnalisis(NuevoAnalisis a) async {
    final id = await _rpc<dynamic>('calidad_registrar_analisis', {
      'p_preparado_id': a.preparadoId,
      'p_brix_diluido': a.brixDiluido,
      'p_ph': a.ph,
      'p_resultado': a.resultado,
      'p_aspecto': a.aspecto,
      'p_accion_tomada': a.accionTomada,
      'p_observaciones': a.observaciones,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> actualizarAnalisis(int id, {String? accionTomada, String? observaciones}) =>
      _rpc<dynamic>('calidad_actualizar_analisis', {
        'p_id': id,
        'p_accion_tomada': accionTomada,
        'p_observaciones': observaciones,
      });
}
