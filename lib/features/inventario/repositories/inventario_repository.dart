import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/almacen.dart';
import '../models/categoria_inv.dart';
import '../models/conteo_nuevo.dart';
import '../models/existencia_item.dart';
import '../models/item_inventario.dart';
import '../models/movimiento_inv.dart';

/// Acceso a datos del inventario por almacenes. Solo consulta y guarda: las
/// validaciones y los permisos son del service (y, en última instancia, del
/// servidor con RLS).
abstract class InventarioRepository {
  Future<List<Almacen>> almacenes();
  Future<List<CategoriaInv>> categorias(String almacenId);

  /// Todas las categorías de todos los almacenes: hace falta para mostrar la
  /// ruta completa de un ítem que un almacén recibió de otro (ej. Soplado
  /// recibe preformas catalogadas por Almacén General).
  Future<List<CategoriaInv>> categoriasTodas();
  Future<List<ExistenciaItem>> existencias(String almacenId);
  Future<ItemInventario> item(int id);
  Future<void> crearItem(ItemInventario item);
  Future<void> actualizarItem(ItemInventario item);
  Future<void> desactivarItem(int id);
  Future<void> registrarConteo({
    required int itemId,
    required String almacenId,
    required double cantidadReal,
    double? cajas,
    int? unidadesPorCaja,
    String? observaciones,
  });

  /// Guarda varios conteos en un solo envío: o entran todos o ninguno.
  Future<void> registrarConteos(List<ConteoNuevo> conteos);

  /// Últimos movimientos de un ítem en un almacén (el más nuevo primero).
  Future<List<MovimientoInv>> movimientos(int itemId, String almacenId, {int limite = 100});

  /// Ingreso o salida manual. El servidor valida permiso, stock y motivo.
  Future<void> registrarMovimiento({
    required int itemId,
    required String almacenId,
    required String tipo,
    required double cantidad,
    required String motivo,
  });

  /// Contra-asiento de un movimiento manual.
  Future<void> revertirMovimiento(int movimientoId, String motivo);

  /// Salida sin pedido formal ni firma (ej. termocontraíbles): la cantidad
  /// de rollos es solo referencia, lo que descuenta stock es el peso real.
  Future<void> registrarSalidaDirecta({
    required int itemId,
    required String areaDestino,
    required double pesoReal,
    double? cantidadRollos,
    String? motivo,
    String almacenId,
  });
}

/// Una regla de negocio del servidor rechazó la operación (mensaje ya listo
/// para mostrar).
class ErrorNegocioInventario implements Exception {
  final String mensaje;
  const ErrorNegocioInventario(this.mensaje);
  @override
  String toString() => mensaje;
}

class SupabaseInventarioRepository implements InventarioRepository {
  static const _almacenes = 'inv_almacenes';
  static const _categorias = 'inv_categorias';
  static const _items = 'inv_items';
  static const _conteos = 'inv_conteos';
  static const _existencia = 'inv_existencia';

  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<Almacen>> almacenes() async {
    final filas = await _db
        .from(_almacenes)
        .select()
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Almacen.fromMap(f)];
  }

  @override
  Future<List<CategoriaInv>> categorias(String almacenId) async {
    final filas = await _db
        .from(_categorias)
        .select()
        .eq('almacen_id', almacenId)
        .order('orden')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) CategoriaInv.fromMap(f)];
  }

  @override
  Future<List<CategoriaInv>> categoriasTodas() async {
    final filas = await _db
        .from(_categorias)
        .select()
        .order('almacen_id')
        .order('orden')
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) CategoriaInv.fromMap(f)];
  }

  @override
  Future<List<ExistenciaItem>> existencias(String almacenId) async {
    final filas = await _db
        .from(_existencia)
        .select()
        .eq('almacen_id', almacenId)
        .order('detalle')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ExistenciaItem.fromMap(f)];
  }

  @override
  Future<ItemInventario> item(int id) async {
    final fila = await _db
        .from(_items)
        .select()
        .eq('id', id)
        .single()
        .timeout(SupabaseService.timeoutRed);
    return ItemInventario.fromMap(fila);
  }

  @override
  Future<void> crearItem(ItemInventario item) async {
    await _db.from(_items).insert(item.toMap()).timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<void> actualizarItem(ItemInventario item) async {
    await _db
        .from(_items)
        .update(item.toMap())
        .eq('id', item.id!)
        .timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<void> desactivarItem(int id) async {
    await _db
        .from(_items)
        .update({'activo': false})
        .eq('id', id)
        .timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<void> registrarConteo({
    required int itemId,
    required String almacenId,
    required double cantidadReal,
    double? cajas,
    int? unidadesPorCaja,
    String? observaciones,
  }) async {
    await _db.from(_conteos).insert({
      'item_id': itemId,
      'almacen_id': almacenId,
      'cantidad_real': cantidadReal,
      'cajas': cajas,
      'unidades_por_caja': unidadesPorCaja,
      'observaciones': observaciones,
    }).timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<void> registrarConteos(List<ConteoNuevo> conteos) async {
    if (conteos.isEmpty) return;
    await _db
        .from(_conteos)
        .insert([for (final c in conteos) c.toMap()]).timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<List<MovimientoInv>> movimientos(int itemId, String almacenId,
      {int limite = 100}) async {
    final filas = await _db
        .from('inv_movimientos_detalle')
        .select()
        .eq('item_id', itemId)
        .eq('almacen_id', almacenId)
        .order('fecha', ascending: false)
        .order('id', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) MovimientoInv.fromMap(f)];
  }

  Future<void> _rpc(String funcion, Map<String, dynamic> params) async {
    try {
      await _db.rpc(funcion, params: params).timeout(SupabaseService.timeoutRed);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw ErrorNegocioInventario(e.message);
      rethrow;
    }
  }

  @override
  Future<void> registrarMovimiento({
    required int itemId,
    required String almacenId,
    required String tipo,
    required double cantidad,
    required String motivo,
  }) =>
      _rpc('inv_registrar_movimiento', {
        'p_item': itemId,
        'p_almacen': almacenId,
        'p_tipo': tipo,
        'p_cantidad': cantidad,
        'p_motivo': motivo,
      });

  @override
  Future<void> revertirMovimiento(int movimientoId, String motivo) =>
      _rpc('inv_revertir_movimiento', {'p_id': movimientoId, 'p_motivo': motivo});

  @override
  Future<void> registrarSalidaDirecta({
    required int itemId,
    required String areaDestino,
    required double pesoReal,
    double? cantidadRollos,
    String? motivo,
    String almacenId = 'general',
  }) =>
      _rpc('inv_registrar_salida_directa', {
        'p_item_id': itemId,
        'p_area_destino': areaDestino,
        'p_peso_real': pesoReal,
        'p_cantidad_rollos': cantidadRollos,
        'p_motivo': motivo,
        'p_almacen_id': almacenId,
      });
}
