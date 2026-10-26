import '../../../services/supabase_service.dart';
import '../../../shared/realtime.dart';

export '../../../shared/realtime.dart' show Suscripcion, SuscripcionNula;

/// Acceso a datos de Informes: solo lectura, filas de una tabla o vista en un
/// rango de fechas. No calcula nada; el service agrega y arma el informe.
abstract class InformesRepository {
  /// Filas de [tabla] con [columnaFecha] en [desde, hasta). Trae todas
  /// (pagina de a 1000): un mes de corridas no tiene por qué entrar en una.
  Future<List<Map<String, dynamic>>> filas({
    required String tabla,
    required String select,
    required String columnaFecha,
    required DateTime desde,
    required DateTime hasta,
    bool fechaEsDia = true,
  });

  /// Avisa cuando cambia cualquiera de las tablas de las que salen los
  /// informes (v41/v42/v43 las agregan a la publicación de Realtime).
  Suscripcion escucharCambios(void Function() onCambio);
}

class SupabaseInformesRepository implements InformesRepository {
  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<Map<String, dynamic>>> filas({
    required String tabla,
    required String select,
    required String columnaFecha,
    required DateTime desde,
    required DateTime hasta,
    bool fechaEsDia = true,
  }) {
    // Columna `date`: se compara con el día; `timestamptz`: con el instante
    // (en hora local, convertido a UTC para que el corte del día sea el de acá).
    final d = fechaEsDia ? _dia(desde) : desde.toUtc().toIso8601String();
    final h = fechaEsDia ? _dia(hasta) : hasta.toUtc().toIso8601String();
    return SupabaseService.todasLasFilas((ini, fin) => SupabaseService.client
        .from(tabla)
        .select(select)
        .gte(columnaFecha, d)
        .lt(columnaFecha, h)
        .order(columnaFecha)
        .range(ini, fin));
  }

  @override
  Suscripcion escucharCambios(void Function() onCambio) => escucharTablas(
        'informes_cambios',
        const [
          'jarabes_preparados',
          'soplado_corridas',
          'llenadora_corridas',
          'codificacion_corridas',
          'calidad_analisis',
          'salidas_reportes',
          'salidas_reporte_lineas',
          'mermas_registros',
          'mermas_causas',
          'inv_movimientos',
          'compras_pedidos',
          'soda_entregas',
        ],
        onCambio,
      );
}
