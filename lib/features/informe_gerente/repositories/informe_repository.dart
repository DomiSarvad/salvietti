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
        // Sin orden, el límite se quedaba con 200 filas cualesquiera (podían
        // faltar los días más nuevos). Del más reciente al más antiguo.
        .order('fecha', ascending: false)
        .order('sabor')
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ResumenProduccion.fromMap(f)];
  }

  @override
  Future<List<DetalleMermaArea>> mermaDe({required DateTime fecha, required int saborId}) async {
    final f = fecha.toIso8601String().split('T').first;
    try {
      final filas = await _db
          .from('mermas_consolidado')
          .select('area, total_merma, porcentaje, alerta, motivo')
          .eq('fecha', f)
          .eq('sabor_id', saborId)
          .timeout(SupabaseService.timeoutRed);
      return [for (final row in filas) DetalleMermaArea.fromMap(row)];
    } on PostgrestException catch (e) {
      // 42703 = columna inexistente: `sabor_id` se le agregó a la vista en
      // v35 después de publicada, y una base donde v35 no se volvió a correr
      // no la tiene.
      if (e.code == '42703' || e.code == '42P01') {
        throw const ErrorInforme('A la base le falta una actualización: hay que volver a '
            'ejecutar schema_v35_mermas.sql en Supabase.');
      }
      rethrow;
    }
  }
}
