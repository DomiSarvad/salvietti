import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/realtime.dart';
import '../models/aviso_campana.dart';

export '../../../shared/realtime.dart' show Suscripcion, SuscripcionNula;

/// Acceso a datos de la campana: solo cuenta pendientes (no trae detalle) y
/// guarda en esta compu qué respuestas ya se vieron. Cada consulta puede
/// fallar sola (ej. el rol no ve pedidos de compra): el service la ignora.
abstract class CampanaRepository {
  Future<int> comprasPendientes();
  Future<int> solicitudesPendientes();

  /// Recetas en estado "propuesta" según qué visto bueno les falta.
  Future<int> recetasEsperando({required String falta}); // 'gerente' | 'calidad' | 'produccion'

  Future<List<RespuestaPropia>> respuestasPropias(String usuarioId, DateTime desde);

  Set<String> vistos(String usuarioId);
  Future<void> marcarVistos(String usuarioId, Iterable<String> claves);

  Suscripcion escucharCambios(void Function() onCambio);
}

class SupabaseCampanaRepository implements CampanaRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<int> comprasPendientes() async => (await _db
          .from('compras_pedidos')
          .select('id')
          .eq('estado', 'pendiente')
          .timeout(SupabaseService.timeoutRed))
      .length;

  @override
  Future<int> solicitudesPendientes() async => (await _db
          .from('solicitudes_gerencia')
          .select('id')
          .eq('estado', 'pendiente')
          .timeout(SupabaseService.timeoutRed))
      .length;

  @override
  Future<int> recetasEsperando({required String falta}) async {
    var q = _db.from('jarabes_recetas').select('id').eq('estado', 'propuesta');
    switch (falta) {
      case 'gerente': // ya tiene los dos vistos buenos
        q = q.not('aprobada_calidad_por', 'is', null).not('aprobada_produccion_por', 'is', null);
      case 'calidad':
        q = q.isFilter('aprobada_calidad_por', null);
      case 'produccion':
        q = q.isFilter('aprobada_produccion_por', null);
    }
    return (await q.timeout(SupabaseService.timeoutRed)).length;
  }

  @override
  Future<List<RespuestaPropia>> respuestasPropias(String usuarioId, DateTime desde) async {
    final out = <RespuestaPropia>[];
    final d = desde.toUtc().toIso8601String();
    try {
      final s = await _db
          .from('solicitudes_gerencia')
          .select('id')
          .eq('solicitante', usuarioId)
          .neq('estado', 'pendiente')
          .gte('resuelta_en', d)
          .timeout(SupabaseService.timeoutRed);
      out.addAll([for (final f in s) RespuestaPropia('solicitud:${f['id']}', 'solicitud')]);
    } catch (_) {}
    try {
      final c = await _db
          .from('compras_pedidos')
          .select('id')
          .eq('solicitante', usuarioId)
          .inFilter('estado', ['aprobado', 'rechazado'])
          .gte('resuelto_en', d)
          .timeout(SupabaseService.timeoutRed);
      out.addAll([for (final f in c) RespuestaPropia('compra:${f['id']}', 'compra')]);
    } catch (_) {}
    return out;
  }

  // Vistos: por usuario y por compu (Hive), como los tours de ayuda.
  Box get _box => Hive.box(HiveBoxes.preferencias);
  String _clave(String u) => 'campana_vistos_$u';

  @override
  Set<String> vistos(String usuarioId) =>
      ((_box.get(_clave(usuarioId)) as List?) ?? const []).cast<String>().toSet();

  @override
  Future<void> marcarVistos(String usuarioId, Iterable<String> claves) async {
    final todos = {...vistos(usuarioId), ...claves};
    // Solo hace falta recordar lo reciente (las respuestas de más de 14 días ya
    // no se consultan): se limita para que la lista no crezca para siempre.
    final lista = todos.toList();
    await _box.put(_clave(usuarioId), lista.length > 500 ? lista.sublist(lista.length - 500) : lista);
  }

  @override
  Suscripcion escucharCambios(void Function() onCambio) => escucharTablas(
      'campana', const ['compras_pedidos', 'solicitudes_gerencia', 'jarabes_recetas'], onCambio);
}
