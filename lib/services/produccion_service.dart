import '../models/produccion.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';

/// Planificación diaria de producción ("lo que el ingeniero organizó
/// para el día") y el "marcado tipo checklist" que descuenta
/// automáticamente materia prima según la fórmula de cada sabor.
///
/// El descuento real ocurre en el servidor (trigger
/// `completar_plan_detalle` en schema.sql) para que sea atómico y
/// consistente sin importar desde qué dispositivo se marque.
class ProduccionService {
  static Future<List<Formula>> listarFormulas() async {
    final data = await SupabaseService.client
        .from('formulas')
        .select()
        .eq('activo', true)
        .order('sabor');
    return List<Map<String, dynamic>>.from(data)
        .map((m) => Formula.fromMap(m))
        .toList();
  }

  /// Obtiene (o crea si no existe) el plan de producción de hoy.
  static Future<PlanProduccion> planDeHoy(String usuarioId) async {
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final existente = await SupabaseService.client
        .from('plan_produccion')
        .select('*, plan_produccion_detalle(*, formulas(sabor))')
        .eq('fecha', hoy)
        .maybeSingle();

    if (existente != null) return PlanProduccion.fromMap(existente);

    final nuevo = await SupabaseService.client
        .from('plan_produccion')
        .insert({'fecha': hoy, 'creado_por': usuarioId})
        .select('*, plan_produccion_detalle(*, formulas(sabor))')
        .single();
    return PlanProduccion.fromMap(nuevo);
  }

  /// Agrega un sabor con sus litros planificados al plan del día.
  static Future<void> agregarSaborAlPlan({
    required String planId,
    required String formulaId,
    required double litros,
    required String usuarioId,
  }) async {
    await SupabaseService.client.from('plan_produccion_detalle').insert({
      'plan_id': planId,
      'formula_id': formulaId,
      'litros_planificados': litros,
    });
    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'planificar_produccion',
      tablaAfectada: 'plan_produccion_detalle',
      detalle: {'litros': litros},
    );
  }

  /// "Marca de la lista" un sabor como completado: el trigger del
  /// servidor descuenta automáticamente cada materia prima de la
  /// fórmula, multiplicada por (litros_planificados / rendimiento).
  static Future<void> marcarComoCompletado({
    required String detalleId,
    required String usuarioId,
  }) async {
    await SupabaseService.client.from('plan_produccion_detalle').update({
      'completado': true,
      'completado_por': usuarioId,
    }).eq('id', detalleId);

    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'completar_produccion',
      tablaAfectada: 'plan_produccion_detalle',
      registroId: detalleId,
    );
  }

  /// Crea o actualiza la receta de un sabor (solo Almacén / Jefe de Prod.).
  static Future<void> guardarFormula({
    String? formulaId,
    required String sabor,
    required double rendimientoLitros,
    required List<Map<String, dynamic>> detalle, // {materia_prima_id, cantidad_por_lote}
  }) async {
    String id;
    if (formulaId == null) {
      final creada = await SupabaseService.client
          .from('formulas')
          .insert({'sabor': sabor, 'rendimiento_litros': rendimientoLitros})
          .select()
          .single();
      id = creada['id'];
    } else {
      id = formulaId;
      await SupabaseService.client
          .from('formulas')
          .update({'sabor': sabor, 'rendimiento_litros': rendimientoLitros})
          .eq('id', id);
      await SupabaseService.client
          .from('formula_detalle')
          .delete()
          .eq('formula_id', id);
    }
    for (final d in detalle) {
      await SupabaseService.client.from('formula_detalle').insert({
        'formula_id': id,
        'materia_prima_id': d['materia_prima_id'],
        'cantidad_por_lote': d['cantidad_por_lote'],
      });
    }
  }
}
