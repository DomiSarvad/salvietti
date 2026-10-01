import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/permisos_modelos.dart';

/// Acceso a `app_modulos`/`permisos_rol` (schema_v17). Sin reglas de
/// negocio: la RLS de `permisos_rol` ya exige ser Gerente con
/// `tiene_permiso('permisos','editar')` para escribir, y un trigger en el
/// servidor impide sacarle a Gerente el acceso a Usuarios o a Permisos.
abstract class PermisosRepository {
  Future<List<ModuloApp>> modulos();

  /// Los pares `modulo:accion` que ya tiene ese rol.
  Future<Set<String>> permisosDeRol(String rol);

  Future<void> otorgar(String rol, String modulo, String accion);
  Future<void> revocar(String rol, String modulo, String accion);
}

class SupabasePermisosRepository implements PermisosRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<ModuloApp>> modulos() async {
    final filas = await _db
        .from('app_modulos')
        .select('id, nombre')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ModuloApp.fromMap(f)];
  }

  @override
  Future<Set<String>> permisosDeRol(String rol) async {
    final filas = await _db
        .from('permisos_rol')
        .select('modulo, accion')
        .eq('rol', rol)
        .timeout(SupabaseService.timeoutRed);
    return {for (final f in filas) '${f['modulo']}:${f['accion']}'};
  }

  @override
  Future<void> otorgar(String rol, String modulo, String accion) async {
    // upsert en vez de insert: (rol, modulo, accion) es la clave primaria,
    // así que tocar el mismo checkbox dos veces seguido (doble clic, red
    // lenta) no revienta con un error de clave duplicada.
    await _db.from('permisos_rol').upsert({'rol': rol, 'modulo': modulo, 'accion': accion});
  }

  @override
  Future<void> revocar(String rol, String modulo, String accion) async {
    await _db
        .from('permisos_rol')
        .delete()
        .eq('rol', rol)
        .eq('modulo', modulo)
        .eq('accion', accion);
  }
}
