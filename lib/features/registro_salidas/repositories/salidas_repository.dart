import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/salidas_modelos.dart';

/// Acceso a datos de Registro de salidas. Las escrituras pasan por
/// funciones del servidor (validan permisos y son atómicas).
abstract class SalidasRepository {
  Future<List<Sabor>> sabores();
  Future<List<Presentacion>> presentaciones();
  Future<Set<int>> presentacionesDe(int saborId);
  Future<List<ReporteSalidas>> reportes({int limite = 60});
  Future<List<LineaSalidas>> lineasDe(int reporteId);
  Future<List<PlanillaFila>> planilla({int limite = 60});

  Future<int> crearReporte(String turno);
  Future<int> guardarLinea(int reporteId, DatosLinea datos);
  Future<void> eliminarLinea(int idLinea);
  Future<void> cerrarReporte(int id, String? observaciones);
}

class SupabaseSalidasRepository implements SalidasRepository {
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
        .select('id, nombre, material')
        .order('material')
        .order('ml')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Presentacion.fromMap(f)];
  }

  @override
  Future<Set<int>> presentacionesDe(int saborId) async {
    final filas = await _db
        .from('sabor_presentacion')
        .select('presentacion_id')
        .eq('sabor_id', saborId)
        .timeout(SupabaseService.timeoutRed);
    return {for (final f in filas) (f['presentacion_id'] as num).toInt()};
  }

  @override
  Future<List<ReporteSalidas>> reportes({int limite = 60}) async {
    final filas = await _db
        .from('salidas_reportes')
        .select()
        .order('fecha', ascending: false)
        .order('turno')
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ReporteSalidas.fromMap(f)];
  }

  @override
  Future<List<LineaSalidas>> lineasDe(int reporteId) async {
    final filas = await _db
        .from('salidas_reporte_detalle')
        .select()
        .eq('reporte_id', reporteId)
        .order('id')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) LineaSalidas.fromMap(f)];
  }

  @override
  Future<List<PlanillaFila>> planilla({int limite = 60}) async {
    final filas = await _db
        .from('salidas_planilla')
        .select()
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) PlanillaFila.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioSalidas(e.message);
      rethrow;
    }
  }

  @override
  Future<int> crearReporte(String turno) async {
    final id = await _rpc<dynamic>('salidas_crear_reporte', {'p_turno': turno});
    return (id as num).toInt();
  }

  @override
  Future<int> guardarLinea(int reporteId, DatosLinea d) async {
    final id = await _rpc<dynamic>('salidas_guardar_linea', {
      'p_reporte_id': reporteId,
      'p_sabor_id': d.saborId,
      'p_presentacion_id': d.presentacionId,
      'p_hora_inicio': d.horaInicio?.toIso8601String(),
      'p_hora_fin': d.horaFin?.toIso8601String(),
      'p_pet_palets': d.petPalets,
      'p_pet_paquetes_libres': d.petPaquetesLibres,
      'p_pet_botellas_libres': d.petBotellasLibres,
      'p_vid_filas': d.vidFilas,
      'p_vid_cajas_libres': d.vidCajasLibres,
      'p_vid_botellas_libres': d.vidBotellasLibres,
      'p_id_linea': d.id,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> eliminarLinea(int idLinea) =>
      _rpc<dynamic>('salidas_eliminar_linea', {'p_id_linea': idLinea});

  @override
  Future<void> cerrarReporte(int id, String? observaciones) => _rpc<dynamic>(
      'salidas_cerrar_reporte', {'p_id': id, 'p_observaciones': observaciones});
}
