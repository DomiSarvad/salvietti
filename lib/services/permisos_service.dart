import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Permisos del rol del usuario (tabla `permisos_rol`).
class PermisosService {
  /// Los permisos del rol como "modulo:accion", o null si no se pudieron
  /// consultar (sin conexión, o la migración v17 todavía no se ejecutó). En
  /// ese caso la app cae a las reglas anteriores por rol; el servidor sigue
  /// decidiendo igual.
  static Future<Set<String>?> delRol(String rol) async {
    try {
      final filas = await SupabaseService.client
          .from('permisos_rol')
          .select('modulo, accion')
          .eq('rol', rol)
          .timeout(SupabaseService.timeoutRed);
      return {for (final f in filas) '${f['modulo']}:${f['accion']}'};
    } catch (e) {
      // Sin esto el menú se ve incompleto y no hay forma de saber por qué.
      debugPrint('PermisosService.delRol($rol) falló: $e');
      return null;
    }
  }
}
