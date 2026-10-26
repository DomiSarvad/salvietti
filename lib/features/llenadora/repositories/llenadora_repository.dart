import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/filas_sin_subir.dart';
import '../models/llenadora_modelos.dart';

/// Acceso a datos de Llenadora. Las escrituras pasan por funciones del
/// servidor (validan permisos y son atómicas).
abstract class LlenadoraRepository {
  Future<List<Sabor>> sabores();
  Future<List<Presentacion>> presentaciones();
  Future<Set<int>> presentacionesDe(int saborId);
  Future<List<PreparadoJarabes>> preparadosDe(int saborId);
  Future<List<ItemInventario>> tapas({String? busqueda});
  Future<List<CorridaLlenadora>> corridas({int limite = 200});
  Future<List<AvanceLlenadora>> avance();

  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? preparadoId,
    String? nLotePreparado,
    String? tanque,
    int? itemTapaId,
  });
  Future<void> finalizarCorrida(int id, FinalizarCorridaLlenadora datos);
  Future<void> anularCorrida(int id, String motivo);
}

class SupabaseLlenadoraRepository implements LlenadoraRepository {
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
  Future<List<PreparadoJarabes>> preparadosDe(int saborId) async {
    final filas = await _db
        .from('jarabes_preparados')
        .select('id, sabor_id, n_lote, tanque')
        .eq('sabor_id', saborId)
        .eq('estado', 'finalizada')
        .order('n_lote', ascending: false)
        .limit(20)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) PreparadoJarabes.fromMap(f)];
  }

  @override
  Future<List<ItemInventario>> tapas({String? busqueda}) async {
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
  Future<List<CorridaLlenadora>> corridas({int limite = 200}) async {
    final filas = await _db
        .from('llenadora_corridas')
        .select('*, sabores(nombre), presentaciones(nombre), inv_items(detalle, unidad)')
        .order('hora_inicio', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [...await _sinSubir(), for (final f in filas) CorridaLlenadora.fromMap(f)];
  }

  /// Corridas iniciadas sin internet que siguen en la cola (ver filasSinSubir).
  Future<List<CorridaLlenadora>> _sinSubir() async {
    final filas = filasSinSubir('llenadora_iniciar_corrida',
        cierran: const ['llenadora_finalizar_corrida', 'llenadora_anular_corrida']);
    if (filas.isEmpty) return const [];
    var sab = <int, String>{}, pre = <int, String>{};
    try {
      sab = {for (final s in await sabores()) s.id: s.nombre};
      pre = {for (final p in await presentaciones()) p.id: p.nombre};
    } catch (_) {
      // Sin copia de los catálogos: la tarjeta sale sin nombres, pero sale.
    }
    return [
      for (final f in filas)
        CorridaLlenadora.fromMap({
          ...f,
          'sabores': {'nombre': sab[f['sabor_id']]},
          'presentaciones': {'nombre': pre[f['presentacion_id']]},
        }),
    ];
  }

  @override
  Future<List<AvanceLlenadora>> avance() async {
    final filas = await _db
        .from('llenadora_avance')
        .select()
        .order('sabor')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AvanceLlenadora.fromMap(f)];
  }

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioLlenadora(e.message);
      rethrow;
    }
  }

  @override
  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? preparadoId,
    String? nLotePreparado,
    String? tanque,
    int? itemTapaId,
  }) async {
    final id = await _rpc<dynamic>('llenadora_iniciar_corrida', {
      'p_turno': turno,
      'p_sabor_id': saborId,
      'p_presentacion_id': presentacionId,
      'p_preparado_id': preparadoId,
      'p_n_lote_preparado': nLotePreparado,
      'p_tanque': tanque,
      'p_item_tapa_id': itemTapaId,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorridaLlenadora d) async {
    await _rpc<dynamic>('llenadora_finalizar_corrida', {
      'p_id': id,
      'p_botellas_llenadas': d.botellasLlenadas,
      'p_botellas_desechadas': d.botellasDesechadas,
      'p_tapas_usadas': d.tapasUsadas,
      'p_tapas_desechadas': d.tapasDesechadas,
      'p_rebalse': d.rebalse,
      'p_motivo_merma': d.motivoMerma,
      'p_observaciones': d.observaciones,
    });
  }

  @override
  Future<void> anularCorrida(int id, String motivo) async {
    await _rpc<dynamic>('llenadora_anular_corrida', {'p_id': id, 'p_motivo': motivo});
  }
}
