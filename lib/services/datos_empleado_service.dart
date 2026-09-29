import '../models/datos_empleado.dart';
import 'supabase_service.dart';

/// Lectura y escritura de los datos personales del empleado. Las políticas del
/// servidor solo dejan ver/editar la fila propia (o cualquiera, al Gerente).
class DatosEmpleadoService {
  /// Los datos de un usuario, o null si todavía no cargó ninguno. Lanza si no
  /// se puede consultar (sin conexión, o tabla inexistente).
  static Future<DatosEmpleado?> obtener(String usuarioId) async {
    final fila = await SupabaseService.client
        .from('datos_empleado')
        .select()
        .eq('usuario_id', usuarioId)
        .maybeSingle()
        .timeout(SupabaseService.timeoutRed);
    return fila == null ? null : DatosEmpleado.fromMap(fila);
  }

  /// Datos de todos los usuarios, por id (solo el Gerente los obtiene; para
  /// cualquier otro rol viene vacío o solo la fila propia).
  static Future<Map<String, DatosEmpleado>> obtenerTodos() async {
    final data = await SupabaseService.client
        .from('datos_empleado')
        .select()
        .timeout(SupabaseService.timeoutRed);
    return {
      for (final f in List<Map<String, dynamic>>.from(data))
        f['usuario_id'] as String: DatosEmpleado.fromMap(f)
    };
  }

  /// Crea o actualiza la fila. [comoGerente] permite además fijar la fecha de
  /// ingreso (el servidor la ignora si quien guarda no es Gerente).
  static Future<void> guardar(
    String usuarioId,
    DatosEmpleado datos, {
    bool comoGerente = false,
  }) async {
    await SupabaseService.client.from('datos_empleado').upsert({
      'usuario_id': usuarioId,
      ...datos.toMap(incluirFechaIngreso: comoGerente),
    }, onConflict: 'usuario_id').timeout(SupabaseService.timeoutRed);
  }
}
