import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/insumo.dart';
import '../models/movimiento.dart';
import 'hive_service.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';

/// CRUD unificado para tapas / preformas / materia_prima.
/// Lee siempre intentando el servidor primero; si falla (sin red) usa
/// el caché de Hive. Los movimientos (entradas/salidas) se registran
/// online si hay conexión, o se encolan localmente si no la hay.
class InventarioService {
  static const tablas = ['tapas', 'preformas', 'materia_prima'];

  static Future<List<Insumo>> listar(String tabla,
      {bool soloActivos = true}) async {
    try {
      var query = SupabaseService.client.from(tabla).select();
      if (soloActivos) query = query.eq('activo', true);
      final data = await query.order('detalle');
      final lista = List<Map<String, dynamic>>.from(data);
      await HiveService.guardarCatalogo(tabla, lista);
      return lista.map((m) => Insumo.fromMap(m, tabla)).toList();
    } catch (_) {
      // Sin conexión: se sirve desde el caché local.
      final lista = HiveService.leerCatalogo(tabla);
      return lista
          .where((m) => !soloActivos || (m['activo'] ?? true))
          .map((m) => Insumo.fromMap(m, tabla))
          .toList();
    }
  }

  /// Trae el catálogo completo de las 3 tablas (para dashboard/alertas).
  static Future<List<Insumo>> listarTodo() async {
    final resultados = await Future.wait(tablas.map((t) => listar(t)));
    return resultados.expand((e) => e).toList();
  }

  static Future<void> crear(Insumo insumo, String usuarioId) async {
    final inserted = await SupabaseService.client
        .from(insumo.tabla)
        .insert(insumo.toMap())
        .select()
        .single();
    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'crear',
      tablaAfectada: insumo.tabla,
      registroId: inserted['id'],
      detalle: {'codigo': inserted['codigo'], 'detalle': insumo.detalle},
    );
  }

  static Future<void> actualizar(Insumo insumo, String usuarioId) async {
    await SupabaseService.client
        .from(insumo.tabla)
        .update(insumo.toMap())
        .eq('id', insumo.id);
    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'editar',
      tablaAfectada: insumo.tabla,
      registroId: insumo.id,
    );
  }

  /// Borrado LÓGICO exclusivamente — nunca DELETE físico. Solo Almacén.
  static Future<void> eliminar(
      String tabla, String id, String usuarioId, String motivo) async {
    await BitacoraService.eliminarLogico(
      tabla: tabla,
      registroId: id,
      usuarioId: usuarioId,
      motivo: motivo,
    );
  }

  /// Registra un movimiento (entrada/salida/ajuste). Si hay conexión se
  /// envía directo; si no, se guarda en la cola local para sincronizar
  /// después (manual o automáticamente).
  static Future<bool> registrarMovimiento(Movimiento mov) async {
    final conectividad = await Connectivity().checkConnectivity();
    final hayRed = !conectividad.contains(ConnectivityResult.none);

    if (hayRed) {
      try {
        await SupabaseService.client
            .from('movimientos')
            .insert(mov.toSupabaseMap());
        return true; // enviado directo
      } catch (_) {
        await HiveService.encolarMovimiento(mov);
        return false; // se guardó offline por error de red/servidor
      }
    } else {
      await HiveService.encolarMovimiento(mov);
      return false;
    }
  }
}
