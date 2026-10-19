import '../../../services/supabase_service.dart';
import '../models/presencia.dart';

/// Acceso a la presencia de las áreas (v42). Las dos funciones del servidor
/// están marcadas en `ClienteOffline`: el latido nunca se encola (un "sigo
/// acá" de hace una hora no sirve) y el listado se lee como una consulta.
abstract class PresenciaRepository {
  /// "Sigo conectado, y tengo [pendientes] registros sin subir."
  Future<void> latido(int pendientes);

  /// Quiénes dieron señal en las últimas 12 horas.
  Future<List<PresenciaUsuario>> recientes();
}

class SupabasePresenciaRepository implements PresenciaRepository {
  @override
  Future<void> latido(int pendientes) async {
    await SupabaseService.client
        .rpc('presencia_latido', params: {'p_pendientes': pendientes})
        .timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<List<PresenciaUsuario>> recientes() async {
    final filas = await SupabaseService.client
        .rpc('presencia_listar')
        .timeout(SupabaseService.timeoutRed);
    return [
      for (final f in filas as List) PresenciaUsuario.fromMap(Map<String, dynamic>.from(f as Map))
    ];
  }
}
