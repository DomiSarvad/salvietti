import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../../../shared/filas_sin_subir.dart';
import '../../../shared/realtime.dart';

export '../../../shared/realtime.dart' show Suscripcion, SuscripcionNula;
import '../models/jarabes_modelos.dart';

/// Acceso a datos de Recetas y producción de Jarabes. Las escrituras pasan
/// por funciones del servidor (validan permisos, calculan lote/litros y
/// descuentan insumos de forma atómica).
abstract class JarabesRepository {
  Future<List<Sabor>> sabores();
  Future<List<ItemJarabes>> itemsJarabes({String? busqueda});
  Future<List<ItemReceta>> recetaVigente(int saborId);
  Future<List<RecetaPropuesta>> recetasPendientes();
  Future<List<Preparado>> preparados({int limite = 200});
  Future<List<AvanceSopladoLite>> avanceSoplado();

  /// Avisa cuando cambia algo que muestra la pantalla de Jarabes (sus
  /// preparados, recetas, o el avance de Soplado), para refrescarla sola.
  Suscripcion escucharCambios(void Function() onCambio);

  Future<int> recetaCrear(int saborId, Map<int, double> items);

  /// El cambio de receta lo aprueban Calidad Y Producción por separado; con
  /// las dos, el Gerente la activa reingresando su clave.
  Future<void> recetaAprobarCalidad(int id);
  Future<void> recetaAprobarProduccion(int id);
  Future<void> recetaConfirmarGerente(int id, String clave);
  Future<void> recetaRechazar(int id, String motivo);

  Future<List<VerificacionInsumo>> verificarInsumos(int saborId, double cantidad);
  Future<int> iniciarPreparado({required int saborId, required double cantidad, int? tanque});
  Future<void> finalizarPreparado(int id, {required double brix, String? observaciones});
  Future<void> anularPreparado(int id, String motivo);

  /// Pide a Almacén los ítems que faltan (Módulo 3), para el área 'jarabes'.
  Future<void> pedirFaltantes(Map<int, double> itemsYCantidad);
}

class SupabaseJarabesRepository implements JarabesRepository {
  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<Sabor>> sabores() async {
    final filas = await _db
        .from('sabores')
        .select('id, nombre')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Sabor.fromMap(f)];
  }

  @override
  Future<List<ItemJarabes>> itemsJarabes({String? busqueda}) async {
    var query = _db
        .from('inv_items')
        .select('id, codigo, detalle, unidad, inv_categorias!inner(almacen_id)')
        .eq('activo', true)
        .eq('inv_categorias.almacen_id', 'jarabes');
    if (busqueda != null && busqueda.trim().isNotEmpty) {
      query = query.ilike('detalle', '%${busqueda.trim()}%');
    }
    // Sin texto: el catálogo entero, para buscarlo en memoria (CatalogoLocal).
    final filas = (busqueda == null || busqueda.trim().isEmpty)
        ? await SupabaseService.todasLasFilas((d, h) => query.order('detalle').range(d, h))
        : await query.order('detalle').limit(30).timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemJarabes.fromMap(f)];
  }

  @override
  Future<List<ItemReceta>> recetaVigente(int saborId) async {
    final filas = await _db
        .from('jarabes_receta_vigente')
        .select()
        .eq('sabor_id', saborId)
        .order('detalle')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemReceta.fromMap(f)];
  }

  @override
  Future<List<RecetaPropuesta>> recetasPendientes() async {
    final filas = await _db
        .from('jarabes_recetas')
        .select('*, sabores(nombre), jarabes_receta_items(cantidad_por_preparado, inv_items(detalle, unidad))')
        .eq('estado', 'propuesta')
        .order('creada_en')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) RecetaPropuesta.fromMap(f)];
  }

  @override
  Future<List<Preparado>> preparados({int limite = 200}) async {
    final filas = await _db
        .from('jarabes_preparados')
        .select('*, sabores(nombre)')
        .order('hora_inicio', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [...await _sinSubir(), for (final f in filas) Preparado.fromMap(f)];
  }

  /// Preparados iniciados sin internet que siguen en la cola (ver
  /// filasSinSubir). El N° de lote lo pone el servidor al subir: mientras
  /// tanto va 0 y la tarjeta lo dice.
  Future<List<Preparado>> _sinSubir() async {
    final filas = filasSinSubir('jarabes_iniciar_preparado',
        cierran: const ['jarabes_finalizar_preparado', 'jarabes_anular_preparado'],
        renombrar: const {'p_cantidad': 'cantidad_preparados'});
    if (filas.isEmpty) return const [];
    var sab = <int, String>{};
    try {
      sab = {for (final s in await sabores()) s.id: s.nombre};
    } catch (_) {
      // Sin copia del catálogo: la tarjeta sale sin el nombre, pero sale.
    }
    return [
      for (final f in filas)
        Preparado.fromMap({
          ...f,
          'n_lote': 0,
          'sabores': {'nombre': sab[f['sabor_id']]},
        }),
    ];
  }

  @override
  Future<List<AvanceSopladoLite>> avanceSoplado() async {
    final filas = await _db
        .from('soplado_avance')
        .select('sabor, presentacion, cajas_sopladas')
        .order('sabor')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AvanceSopladoLite.fromMap(f)];
  }

  @override
  Suscripcion escucharCambios(void Function() onCambio) => escucharTablas(
      'jarabes_cambios', const ['jarabes_preparados', 'jarabes_recetas', 'soplado_corridas'], onCambio);

  Future<T> _rpc<T>(String funcion, Map<String, dynamic> params) async {
    try {
      final r = await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
      return r as T;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioJarabes(e.message);
      rethrow;
    }
  }

  @override
  Future<int> recetaCrear(int saborId, Map<int, double> items) async {
    final id = await _rpc<dynamic>('jarabes_receta_crear', {
      'p_sabor_id': saborId,
      'p_items': [
        for (final e in items.entries) {'item_id': e.key, 'cantidad': e.value}
      ],
    });
    return (id as num).toInt();
  }

  @override
  Future<void> recetaAprobarCalidad(int id) =>
      _rpc<dynamic>('jarabes_receta_aprobar_calidad', {'p_id': id});

  @override
  Future<void> recetaAprobarProduccion(int id) =>
      _rpc<dynamic>('jarabes_receta_aprobar_produccion', {'p_id': id});

  @override
  Future<void> recetaConfirmarGerente(int id, String clave) => _rpc<dynamic>(
      'jarabes_receta_confirmar_gerente', {'p_id': id, 'p_clave': clave});

  @override
  Future<void> recetaRechazar(int id, String motivo) =>
      _rpc<dynamic>('jarabes_receta_rechazar', {'p_id': id, 'p_motivo': motivo});

  @override
  Future<List<VerificacionInsumo>> verificarInsumos(int saborId, double cantidad) async {
    final filas = await _rpc<List<dynamic>>('jarabes_verificar_insumos', {
      'p_sabor_id': saborId,
      'p_cantidad': cantidad,
    });
    return [for (final f in filas) VerificacionInsumo.fromMap(Map<String, dynamic>.from(f))];
  }

  @override
  Future<int> iniciarPreparado({required int saborId, required double cantidad, int? tanque}) async {
    final id = await _rpc<dynamic>('jarabes_iniciar_preparado', {
      'p_sabor_id': saborId,
      'p_cantidad': cantidad,
      'p_tanque': tanque,
    });
    return (id as num).toInt();
  }

  @override
  Future<void> finalizarPreparado(int id, {required double brix, String? observaciones}) =>
      _rpc<dynamic>('jarabes_finalizar_preparado', {
        'p_id': id,
        'p_brix': brix,
        'p_observaciones': observaciones,
      });

  @override
  Future<void> anularPreparado(int id, String motivo) =>
      _rpc<dynamic>('jarabes_anular_preparado', {'p_id': id, 'p_motivo': motivo});

  @override
  Future<void> pedirFaltantes(Map<int, double> itemsYCantidad) => _rpc<dynamic>('inv_crear_pedido', {
        'p_area': null, // el servidor la deduce del rol de quien llama
        'p_motivo': 'Faltante detectado al preparar un lote de jarabes',
        'p_lineas': [
          for (final e in itemsYCantidad.entries) {'item_id': e.key, 'cantidad': e.value}
        ],
        'p_entregar': false,
      });
}
