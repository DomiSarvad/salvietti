import '../../services/supabase_service.dart';

/// Recorridos guiados que el usuario con sesión ya vio (`tours_vistos`, v45).
/// En `ClienteOffline` la tabla pasa directo (no se encola): sin internet
/// alcanza con lo que se recuerda en la compu.
abstract class ToursVistosRepository {
  Future<Set<String>> vistos();
  Future<void> marcar(String idTour);
  Future<void> borrarTodos();
}

class SupabaseToursVistosRepository implements ToursVistosRepository {
  static const _tabla = 'tours_vistos';

  @override
  Future<Set<String>> vistos() async {
    final filas = await SupabaseService.client
        .from(_tabla)
        .select('id_tour')
        .timeout(SupabaseService.timeoutRed);
    return {for (final f in filas) f['id_tour'] as String};
  }

  @override
  Future<void> marcar(String idTour) async {
    await SupabaseService.client
        .from(_tabla)
        .upsert({'id_tour': idTour}, onConflict: 'usuario_id,id_tour', ignoreDuplicates: true)
        .timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<void> borrarTodos() async {
    final id = SupabaseService.currentUser?.id;
    if (id == null) return;
    await SupabaseService.client
        .from(_tabla)
        .delete()
        .eq('usuario_id', id)
        .timeout(SupabaseService.timeoutRed);
  }
}
