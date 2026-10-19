import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/realtime.dart';

export '../../../shared/realtime.dart' show Suscripcion;
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
  Suscripcion escucharStock(void Function() onCambio) =>
      escucharTablas('dashboard_stock', const ['inv_movimientos'], onCambio);

  @override
  Suscripcion escucharMermas(void Function() onCambio) => escucharTablas(
        'dashboard_mermas',
        const [
          'mermas_registros',
          'mermas_causas',
          'llenadora_corridas',
          'soplado_corridas',
          'codificacion_corridas',
        ],
        onCambio,
      );
}
