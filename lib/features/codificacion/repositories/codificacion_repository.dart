import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/codificacion_modelos.dart';

/// Acceso a datos de Codificación. Las escrituras pasan por funciones del
/// servidor (validan permisos y son atómicas).
abstract class CodificacionRepository {
  Future<List<Sabor>> sabores();
  Future<List<Presentacion>> presentaciones();
  Future<Set<int>> presentacionesDe(int saborId);
  Future<List<CorridaLlenadoraRef>> corridasLlenadoraDe(int saborId);
  Future<List<ItemInventario>> items({String? busqueda});
  Future<List<CorridaCodificacion>> corridas({int limite = 200});
  Future<List<AvanceCodificacion>> avance();

  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? corridaLlenadoraId,
    String? nLote,
    int? itemSolventeId,
    int? itemTintaId,
  });
  Future<void> finalizarCorrida(int id, FinalizarCorridaCodificacion datos);
  Future<void> anularCorrida(int id, String motivo);
}

class SupabaseCodificacionRepository implements CodificacionRepository {
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
  Future<List<CorridaLlenadoraRef>> corridasLlenadoraDe(int saborId) async {
    final filas = await _db
        .from('llenadora_corridas')
        .select('id, sabor_id, turno')
        .eq('sabor_id', saborId)
        .eq('estado', 'finalizada')
        .order('hora_fin', ascending: false)
        .limit(20)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) CorridaLlenadoraRef.fromMap(f)];
  }

  @override
  Future<List<ItemInventario>> items({String? busqueda}) async {
    var query = _db.from('inv_items').select('id, codigo, detalle, unidad').eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('detalle', '%${busqueda.trim()}%');
    }
    // Sin texto: el catálogo entero, para buscarlo en memoria (CatalogoLocal).
    final filas = (busqueda == null || busqueda.trim().isEmpty)
        ? await SupabaseService.todasLasFilas((d, h) => query.order('detalle').range(d, h))
        : await query.order('detalle').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemInventario.fromMap(f)];
  }

  @override
  Future<List<CorridaCodificacion>> corridas({int limite = 200}) async {
    final filas = await _db
        .from('codificacion_corridas')
        .select('*, sabores(nombre), presentaciones(nombre), '
            'solvente:inv_items!codificacion_corridas_item_solvente_id_fkey(detalle), '
            'tinta:inv_items!codificacion_corridas_item_tinta_id_fkey(detalle)')
        .order('hora_inicio', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) CorridaCodificacion.fromMap(f)];
  }

  @override
  Future<List<AvanceCodificacion>> avance() async {
    final filas = await _db
        .from('codificacion_avance')
        .select()
        .order('sabor')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AvanceCodificacion.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioCodificacion(e.message);
      rethrow;
    }
  }

  @override
  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? corridaLlenadoraId,
    String? nLote,
    int? itemSolventeId,
    int? itemTintaId,
  }) async {
    final id = await _rpc<dynamic>('codificacion_iniciar_corrida', {
      'p_turno': turno,
      'p_sabor_id': saborId,
      'p_presentacion_id': presentacionId,
      'p_corrida_llenadora_id': corridaLlenadoraId,
      'p_n_lote': nLote,
      'p_item_solvente_id': itemSolventeId,
      'p_item_tinta_id': itemTintaId,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorridaCodificacion d) async {
    await _rpc<dynamic>('codificacion_finalizar_corrida', {
      'p_id': id,
      'p_botellas_codificadas': d.botellasCodificadas,
      'p_codigo_impreso': d.codigoImpreso,
      'p_botellas_mal_tapadas': d.botellasMalTapadas,
      'p_tapas_mal_tapadas': d.tapasMalTapadas,
      'p_impurezas': d.impurezas,
      'p_motivo_merma': d.motivoMerma,
      'p_solvente_usado': d.solventeUsado,
      'p_tinta_usada': d.tintaUsada,
      'p_observaciones': d.observaciones,
    });
  }

  @override
  Future<void> anularCorrida(int id, String motivo) async {
    await _rpc<dynamic>('codificacion_anular_corrida', {'p_id': id, 'p_motivo': motivo});
  }
}
