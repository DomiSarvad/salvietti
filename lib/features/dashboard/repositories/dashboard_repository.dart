import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../inventario/models/almacen.dart';
import '../../inventario/models/existencia_item.dart';
import '../../mermas/models/mermas_modelos.dart';
import '../models/dashboard_modelos.dart';

/// Acceso a datos del Inicio: solo lectura, todo de vistas/tablas que ya
/// existen (Módulo 1 y Módulo 9). No valida nada; el service decide qué
/// almacenes le tocan a cada rol y si puede ver mermas.
abstract class DashboardRepository {
  Future<List<Almacen>> almacenes();
  Future<List<ExistenciaItem>> existenciasDe(List<String> almacenIds);
  Future<List<MovimientoReciente>> movimientosRecientes(List<String> almacenIds, {int limite = 12});
  Future<List<EventoMerma>> mermasRecientes({int limite = 30});

  /// Avisa (llamando a [onCambio]) cada vez que cambia algo que afecta el
  /// stock (cualquier movimiento, de cualquier almacén). Devuelve algo para
  /// poder cerrar la suscripción cuando la pantalla se destruye — sin
  /// exponer la clase concreta de Supabase acá, para poder probar el
  /// service con un repositorio falso.
  Suscripcion escucharStock(void Function() onCambio);

  /// Igual que arriba, pero para lo que afecta al resumen de mermas.
  Suscripcion escucharMermas(void Function() onCambio);
}

/// Una suscripción activa (a Realtime u otra cosa) que se puede cancelar.
abstract class Suscripcion {
  void cancelar();
}

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<Almacen>> almacenes() async {
    final filas = await _db
        .from('inv_almacenes')
        .select()
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Almacen.fromMap(f)];
  }

  @override
  Future<List<ExistenciaItem>> existenciasDe(List<String> almacenIds) async {
    if (almacenIds.isEmpty) return [];
    final filas = await _db
        .from('inv_existencia')
        .select()
        .inFilter('almacen_id', almacenIds)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ExistenciaItem.fromMap(f)];
  }

  @override
  Future<List<MovimientoReciente>> movimientosRecientes(List<String> almacenIds,
      {int limite = 12}) async {
    if (almacenIds.isEmpty) return [];
    final filas = await _db
        .from('inv_movimientos')
        .select('id, fecha, almacen_id, tipo, cantidad, motivo, inv_items(codigo, detalle, unidad)')
        .inFilter('almacen_id', almacenIds)
        .order('fecha', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) MovimientoReciente.fromMap(f)];
  }

  @override
  Future<List<EventoMerma>> mermasRecientes({int limite = 30}) async {
    final filas = await _db
        .from('mermas_consolidado')
        .select()
        .order('fecha', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) EventoMerma.fromMap(f)];
  }

  @override
  Suscripcion escucharStock(void Function() onCambio) {
    final canal = _db
        .channel('dashboard_stock')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inv_movimientos',
          callback: (_) => onCambio(),
        )
        .subscribe();
    return _SuscripcionRealtime(canal);
  }

  @override
  Suscripcion escucharMermas(void Function() onCambio) {
    final canal = _db.channel('dashboard_mermas');
    for (final tabla in [
      'mermas_registros',
      'mermas_causas',
      'llenadora_corridas',
      'soplado_corridas',
      'codificacion_corridas',
    ]) {
      canal.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tabla,
        callback: (_) => onCambio(),
      );
    }
    return _SuscripcionRealtime(canal.subscribe());
  }
}

class _SuscripcionRealtime implements Suscripcion {
  final RealtimeChannel _canal;
  const _SuscripcionRealtime(this._canal);
  @override
  void cancelar() => SupabaseService.client.removeChannel(_canal);
}
