import '../models/movimiento.dart';
import 'supabase_service.dart';

/// Ningún movimiento se puede "deshacer" si representa más de este
/// porcentaje del stock actual del ítem — así un error de tipeo grande
/// (que es justo lo que rompe el inventario) nunca se corrige con un
/// clic: esos necesitan un ajuste manual revisado desde Inventario.
const double limiteDeshacerPorcentaje = 0.2;

/// Lecturas del kardex de movimientos (entradas/salidas/ajustes/
/// producción) para el Home y para Reportes. No tiene caché local (no
/// hace falta trabajar con el historial sin conexión): si falla o
/// tarda demasiado, se devuelve una lista vacía en vez de dejar la
/// pantalla cargando para siempre.
class MovimientoService {
  static Future<List<Movimiento>> listarRecientes({int limite = 15}) async {
    try {
      final data = await SupabaseService.client
          .from('movimientos')
          .select()
          .order('created_at', ascending: false)
          .limit(limite)
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data)
          .map((m) => Movimiento.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// [desde]/[hasta] son opcionales: si no se eligen, no se filtra por
  /// fecha (trae todo el historial que corresponda al resto de filtros).
  static Future<List<Movimiento>> listarPorFiltro({
    DateTime? desde,
    DateTime? hasta,
    String? tabla,
    String? itemId,
  }) async {
    try {
      var query = SupabaseService.client.from('movimientos').select();
      if (desde != null) query = query.gte('created_at', desde.toIso8601String());
      if (hasta != null) query = query.lte('created_at', hasta.toIso8601String());
      if (tabla != null) query = query.eq('tabla_origen', tabla);
      if (itemId != null) query = query.eq('item_id', itemId);
      final data = await query
          .order('created_at')
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data)
          .map((m) => Movimiento.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Vencimiento aproximado de cada ítem: la fecha de vencimiento más
  /// próxima (que todavía no pasó) entre sus movimientos de ingreso, tal
  /// como quedaron registrados en "Registrar movimiento". Es una
  /// aproximación (no rastrea qué lote específico queda en stock), pero
  /// alcanza para avisar qué insumos vencen pronto.
  static Future<Map<String, DateTime>> proximosVencimientos(
      {String tabla = 'materia_prima'}) async {
    try {
      final hoy = DateTime.now().toIso8601String().substring(0, 10);
      final data = await SupabaseService.client
          .from('movimientos')
          .select('item_id, fecha_vencimiento')
          .eq('tabla_origen', tabla)
          .not('fecha_vencimiento', 'is', null)
          .gte('fecha_vencimiento', hoy)
          .timeout(SupabaseService.timeoutRed);
      final mapa = <String, DateTime>{};
      for (final fila in List<Map<String, dynamic>>.from(data)) {
        final id = fila['item_id'] as String?;
        final fecha = fila['fecha_vencimiento'] != null
            ? DateTime.tryParse(fila['fecha_vencimiento'])
            : null;
        if (id == null || fecha == null) continue;
        if (!mapa.containsKey(id) || fecha.isBefore(mapa[id]!)) mapa[id] = fecha;
      }
      return mapa;
    } catch (_) {
      return {};
    }
  }

  /// Si [movimiento] es chico en relación al stock actual del ítem, se
  /// puede deshacer con un clic. Excluye además los descuentos
  /// automáticos de producción (`tipo == 'produccion'`, ligados a un
  /// lote de la planificación diaria) y las reversiones mismas.
  static bool puedeDeshacerse(Movimiento movimiento, double cantidadActualItem) {
    if (movimiento.tipo == 'produccion') return false;
    if (movimiento.revierteMovimientoId != null) return false;
    if (cantidadActualItem <= 0) return false;
    return movimiento.cantidad <= cantidadActualItem * limiteDeshacerPorcentaje;
  }

  /// Inserta un ajuste que revierte exactamente el efecto de
  /// [movimiento] sobre el stock (nunca se borra el original: así el
  /// kardex queda completo). Vuelve a validar el límite de seguridad
  /// del lado del cliente antes de escribir, por si el llamador no lo
  /// hizo — nunca confiar solo en que el botón estuvo deshabilitado.
  static Future<void> deshacer({
    required Movimiento movimiento,
    required double cantidadActualItem,
    required String usuarioId,
  }) async {
    if (movimiento.id == null) {
      throw Exception('No se puede deshacer: falta el id del movimiento.');
    }
    if (!puedeDeshacerse(movimiento, cantidadActualItem)) {
      throw Exception(
          'Esta cantidad es demasiado grande para deshacer automáticamente. '
          'Corrígela con un ajuste manual desde Inventario.');
    }
    final cantidadReversa =
        movimiento.tipo == 'salida' ? movimiento.cantidad : -movimiento.cantidad;

    await SupabaseService.client.from('movimientos').insert({
      'tabla_origen': movimiento.tablaOrigen,
      'item_id': movimiento.itemId,
      'tipo': 'ajuste',
      'cantidad': cantidadReversa,
      'unidad_medida': movimiento.unidadMedida,
      'usuario_id': usuarioId,
      'revierte_movimiento_id': movimiento.id,
      'observacion': 'Corrección: deshace el movimiento registrado el '
          '${movimiento.creadoEn}.',
    }).timeout(SupabaseService.timeoutRed);
  }
}
