import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/informe_modelos.dart';

/// Acceso de solo lectura al Informe general de Producción: todo sale de
/// vistas que ya juntan lo que otros módulos registraron.
abstract class InformeRepository {
  Future<List<ResumenProduccion>> resumen({int limite = 200});
  Future<List<DetalleMermaArea>> mermaDe({required DateTime fecha, required int saborId});
}

class SupabaseInformeRepository implements InformeRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<ResumenProduccion>> resumen({int limite = 200}) async {
    final filas = await _db
        .from('informe_produccion_resumen')
        .select()
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ResumenProduccion.fromMap(f)];
  }

  @override
  Future<List<DetalleMermaArea>> mermaDe({required DateTime fecha, required int saborId}) async {
    final f = fecha.toIso8601String().split('T').first;
    final filas = await _db
        .from('mermas_consolidado')
        .select('area, total_merma, porcentaje, alerta, motivo')
        .eq('fecha', f)
        .eq('sabor_id', saborId)
        .timeout(SupabaseService.timeoutRed);
    return [for (final row in filas) DetalleMermaArea.fromMap(row)];
  }
}
