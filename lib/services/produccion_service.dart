import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
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
  /// Las fórmulas no se cachean localmente (no se editan sin conexión),
  /// así que si falla o tarda demasiado se devuelve vacío en vez de dejar
  /// la pantalla de Producción cargando para siempre.
  static Future<List<Formula>> listarFormulas() async {
    try {
      final data = await SupabaseService.client
          .from('formulas')
          .select()
          .eq('activo', true)
          .order('sabor')
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data)
          .map((m) => Formula.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static const _selectPlan =
      '*, plan_produccion_detalle(*, formulas(sabor), '
      'productos_terminados(nombre, envase, litros_por_botella, botellas_por_paquete))';

  /// Obtiene (o crea si no existe) el plan de producción de hoy.
  /// Requiere conexión: el llamador debe manejar la excepción (p. ej.
  /// mostrando "sin conexión" en vez de un spinner infinito) si no la hay.
  static Future<PlanProduccion> planDeHoy(String usuarioId) async {
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final existente = await SupabaseService.client
        .from('plan_produccion')
        .select(_selectPlan)
        .eq('fecha', hoy)
        .maybeSingle()
        .timeout(SupabaseService.timeoutRed);

    if (existente != null) return PlanProduccion.fromMap(existente);

    final nuevo = await SupabaseService.client
        .from('plan_produccion')
        .insert({'fecha': hoy, 'creado_por': usuarioId})
        .select(_selectPlan)
        .single()
        .timeout(SupabaseService.timeoutRed);
    return PlanProduccion.fromMap(nuevo);
  }

  /// Los productos terminados (catálogo de sabor+tamaño+envase) tampoco
  /// se cachean localmente (se administran online, como las fórmulas).
  static Future<List<ProductoTerminado>> listarProductosTerminados() async {
    try {
      final data = await SupabaseService.client
          .from('productos_terminados')
          .select()
          .eq('activo', true)
          .order('nombre')
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data)
          .map((m) => ProductoTerminado.fromMap(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Alta de un producto terminado en el catálogo (solo Almacén/Jefe de
  /// Producción, reforzado por RLS).
  static Future<void> guardarProductoTerminado(ProductoTerminado producto) async {
    await SupabaseService.client
        .from('productos_terminados')
        .insert(producto.toMap());
  }

  /// Cambia nombre, materiales, litros o foto de un producto ya creado.
  static Future<void> actualizarProductoTerminado(ProductoTerminado producto) async {
    await SupabaseService.client
        .from('productos_terminados')
        .update(producto.toMap())
        .eq('id', producto.id)
        .timeout(SupabaseService.timeoutRed);
  }

  /// Sube la foto de un producto (bucket público "productos", v46) y
  /// devuelve su dirección. Necesita internet: no va a la cola.
  static Future<String> subirFotoProducto(Uint8List bytes, String extension) async {
    final ext = extension == 'jpeg' ? 'jpg' : extension;
    final ruta = '${DateTime.now().microsecondsSinceEpoch}.$ext';
    final storage = SupabaseService.client.storage.from('productos');
    await storage.uploadBinary(ruta, bytes,
        fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
    return storage.getPublicUrl(ruta);
  }

  /// Agrega un producto terminado (sabor + tamaño + envase) con sus
  /// litros planificados al plan del día.
  static Future<void> agregarProductoAlPlan({
    required String planId,
    required ProductoTerminado producto,
    required double litros,
    required String usuarioId,
  }) async {
    await SupabaseService.client.from('plan_produccion_detalle').insert({
      'plan_id': planId,
      'producto_terminado_id': producto.id,
      'formula_id': producto.formulaId,
      'litros_planificados': litros,
    });
    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'planificar_produccion',
      tablaAfectada: 'plan_produccion_detalle',
      detalle: {'producto': producto.nombre, 'litros': litros},
    );
  }

  /// "Marca de la lista" un producto como completado: el trigger del
  /// servidor descuenta automáticamente la materia prima de la fórmula
  /// (según litros producidos + merma) y, si el producto tiene preforma
  /// y tapa asociadas, también esas — una por botella producida.
  static Future<void> marcarComoCompletado({
    required String detalleId,
    required String usuarioId,
    required double botellasProducidas,
    double mermaLitros = 0,
    double? litrosProducidos,
  }) async {
    await SupabaseService.client.from('plan_produccion_detalle').update({
      'completado': true,
      'completado_por': usuarioId,
      'botellas_producidas': botellasProducidas,
      'merma_litros': mermaLitros,
      if (litrosProducidos != null) 'litros_producidos': litrosProducidos,
    }).eq('id', detalleId);

    await BitacoraService.registrarAccion(
      usuarioId: usuarioId,
      accion: 'completar_produccion',
      tablaAfectada: 'plan_produccion_detalle',
      registroId: detalleId,
      detalle: {'botellas_producidas': botellasProducidas, 'merma_litros': mermaLitros},
    );
  }

  /// Litros producidos por sabor en un rango de fechas, para el gráfico
  /// de Estadísticas.
  static Future<List<Map<String, dynamic>>> historialProduccion({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    try {
      final data = await SupabaseService.client
          .from('plan_produccion_detalle')
          .select('litros_producidos, completado_en, formulas(sabor), '
              'plan_produccion!inner(fecha)')
          .eq('completado', true)
          .gte('plan_produccion.fecha', desde.toIso8601String().substring(0, 10))
          .lte('plan_produccion.fecha', hasta.toIso8601String().substring(0, 10))
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  /// Detalle de la receta de un sabor (qué materia prima y cuánta por
  /// lote), para la pantalla donde el Jefe de Producción ajusta cuánto
  /// se gasta de cada insumo por producto.
  static Future<List<Map<String, dynamic>>> listarFormulaDetalle(
      String formulaId) async {
    try {
      final data = await SupabaseService.client
          .from('formula_detalle')
          .select('materia_prima_id, cantidad_por_lote, materia_prima(detalle, unidad_medida)')
          .eq('formula_id', formulaId)
          .timeout(SupabaseService.timeoutRed);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
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
