import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'supabase_service.dart';

/// Registra "quién entró y qué hizo" (bitacora_acciones) y gestiona el
/// borrado lógico + su bitácora aparte (bitacora_eliminaciones), tal
/// como exige el requisito: nada se elimina físicamente.
class BitacoraService {
  static String get _dispositivo {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem; // android, ios, windows, linux, macos
    } catch (_) {
      return 'desconocido';
    }
  }

  static Future<void> registrarAccion({
    required String usuarioId,
    required String accion,
    String? tablaAfectada,
    String? registroId,
    Map<String, dynamic>? detalle,
  }) async {
    await SupabaseService.client.from('bitacora_acciones').insert({
      'usuario_id': usuarioId,
      'accion': accion,
      'tabla_afectada': tablaAfectada,
      'registro_id': registroId,
      'detalle': detalle,
      'dispositivo': _dispositivo,
    });
  }

  /// Elimina lógicamente un registro (activo = false) usando la función
  /// `eliminar_logico` del servidor, que además crea automáticamente la
  /// entrada en bitacora_eliminaciones con una copia completa de la fila.
  /// Solo Almacén tiene permiso (verificado también por RLS).
  static Future<void> eliminarLogico({
    required String tabla,
    required String registroId,
    required String usuarioId,
    String? motivo,
  }) async {
    await SupabaseService.client.rpc('eliminar_logico', params: {
      'p_tabla': tabla,
      'p_id': registroId,
      'p_usuario': usuarioId,
      'p_motivo': motivo,
    });
  }

  /// El historial no tiene caché local (no forma parte de los datos que se
  /// necesitan para trabajar sin conexión), así que sin internet simplemente
  /// se devuelve vacío en vez de dejar la pantalla cargando para siempre.
  static Future<List<Map<String, dynamic>>> historialAcciones(
      {int limite = 100}) async {
    try {
      final data = await SupabaseService.client
          .from('bitacora_acciones')
          .select('*, usuarios(nombre_completo, rol)')
          .order('created_at', ascending: false)
          .limit(limite)
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> historialEliminaciones(
      {int limite = 100}) async {
    try {
      final data = await SupabaseService.client
          .from('bitacora_eliminaciones')
          .select('*, usuarios(nombre_completo)')
          .order('created_at', ascending: false)
          .limit(limite)
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }
}
