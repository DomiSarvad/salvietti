import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/filas_sin_subir.dart';
import '../../../shared/realtime.dart';

export '../../../shared/realtime.dart' show Suscripcion, SuscripcionNula;
import '../models/soplado_modelos.dart';

/// Acceso a datos de Soplado. Las escrituras pasan por funciones del
/// servidor (validan permisos, descuentan preforma, son atómicas).
abstract class SopladoRepository {
  Future<List<Sabor>> sabores();
  Future<List<Presentacion>> presentacionesPet();

  /// Presentaciones en las que existe [saborId] (matriz sabor × tamaño).
  Future<Set<int>> presentacionesDe(int saborId);

  Future<List<ItemPreforma>> preformas({String? busqueda});
  Future<List<Proveedor>> proveedores({String? busqueda});
  Future<List<CorridaSoplado>> corridas({int limite = 200});
  Future<List<AvanceSoplado>> avance();

  /// Avisa cuando cambia una corrida (de cualquier persona), para refrescar
  /// la pantalla sola.
  Suscripcion escucharCambios(void Function() onCambio);

  Future<int> iniciarCorrida({
    required int saborId,
    required int presentacionId,
    int? itemPreformaId,
    int? proveedorId,
    String? lotePreforma,
  });
  Future<void> finalizarCorrida(int id, FinalizarCorrida datos);
  Future<void> anularCorrida(int id, String motivo);
}

class SupabaseSopladoRepository implements SopladoRepository {
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
  Future<List<Presentacion>> presentacionesPet() async {
    final filas = await _db
        .from('presentaciones')
        .select('id, nombre, material')
        .eq('material', 'pet')
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
  Future<List<ItemPreforma>> preformas({String? busqueda}) async {
    var query = _db.from('inv_items').select('id, codigo, detalle, unidad').eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('detalle', '%${busqueda.trim()}%');
    }
    // Sin texto: el catálogo entero, para buscarlo en memoria (CatalogoLocal).
    final filas = (busqueda == null || busqueda.trim().isEmpty)
        ? await SupabaseService.todasLasFilas((d, h) => query.order('detalle').range(d, h))
        : await query.order('detalle').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemPreforma.fromMap(f)];
  }

  @override
  Future<List<Proveedor>> proveedores({String? busqueda}) async {
    var query = _db.from('inv_proveedores').select('id, nombre').eq('activo', true);
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('nombre', '%${busqueda.trim()}%');
    }
    // Sin texto: el catálogo entero, para buscarlo en memoria (CatalogoLocal).
    final filas = (busqueda == null || busqueda.trim().isEmpty)
        ? await SupabaseService.todasLasFilas((d, h) => query.order('nombre').range(d, h))
        : await query.order('nombre').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Proveedor.fromMap(f)];
  }

  @override
  Future<List<CorridaSoplado>> corridas({int limite = 200}) async {
    final filas = await _db
        .from('soplado_corridas')
        .select(
            '*, sabores(nombre), presentaciones(nombre), inv_items(detalle, unidad), inv_proveedores(nombre)')
        .order('hora_inicio', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [...await _sinSubir(), for (final f in filas) CorridaSoplado.fromMap(f)];
  }

  /// Corridas iniciadas sin internet que siguen en la cola (ver filasSinSubir).
  Future<List<CorridaSoplado>> _sinSubir() async {
    final filas = filasSinSubir('soplado_iniciar_corrida',
        cierran: const ['soplado_finalizar_corrida', 'soplado_anular_corrida']);
    if (filas.isEmpty) return const [];
    var sab = <int, String>{}, pre = <int, String>{};
    try {
      sab = {for (final s in await sabores()) s.id: s.nombre};
      pre = {for (final p in await presentacionesPet()) p.id: p.nombre};
    } catch (_) {
      // Sin copia de los catálogos: la tarjeta sale sin nombres, pero sale.
    }
    return [
      for (final f in filas)
        CorridaSoplado.fromMap({
          ...f,
          'sabores': {'nombre': sab[f['sabor_id']]},
          'presentaciones': {'nombre': pre[f['presentacion_id']]},
        }),
    ];
  }

  @override
  Future<List<AvanceSoplado>> avance() async {
    final filas = await _db
        .from('soplado_avance')
        .select()
        .order('sabor')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AvanceSoplado.fromMap(f)];
  }

  @override
  Suscripcion escucharCambios(void Function() onCambio) =>
      escucharTablas('soplado_cambios', const ['soplado_corridas'], onCambio);

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioSoplado(e.message);
      rethrow;
    }
  }

  @override
  Future<int> iniciarCorrida({
    required int saborId,
    required int presentacionId,
    int? itemPreformaId,
    int? proveedorId,
    String? lotePreforma,
  }) async {
    final id = await _rpc<dynamic>('soplado_iniciar_corrida', {
      'p_sabor_id': saborId,
      'p_presentacion_id': presentacionId,
      'p_item_preforma_id': itemPreformaId,
      'p_proveedor_id': proveedorId,
      'p_lote_preforma': lotePreforma,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorrida d) async {
    await _rpc<dynamic>('soplado_finalizar_corrida', {
      'p_id': id,
      'p_botellas_sopladas': d.botellasSopladas,
      'p_preformas_usadas': d.preformasUsadas,
      'p_merma_soplado': d.mermaSoplado,
      'p_merma_preforma': d.mermaPreforma,
      'p_botellas_etiquetadas': d.botellasEtiquetadas,
      'p_merma_etiquetado': d.mermaEtiquetado,
      'p_tiempo_parada_minutos': d.tiempoParadaMinutos,
      'p_motivo_parada': d.motivoParada,
      'p_motivo_merma': d.motivoMerma,
      'p_observaciones': d.observaciones,
    });
  }

  @override
  Future<void> anularCorrida(int id, String motivo) async {
    await _rpc<dynamic>('soplado_anular_corrida', {'p_id': id, 'p_motivo': motivo});
  }
}
