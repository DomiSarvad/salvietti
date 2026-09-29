import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/recepciones_modelos.dart';

/// Acceso a datos de las recepciones. Solo consulta y guarda; las
/// validaciones y los permisos son del service y del servidor (RLS).
abstract class RecepcionesRepository {
  Future<List<AlmacenRec>> almacenes();
  Future<List<RecepcionDetalle>> recepciones(String almacenId, {int limite = 200});
  Future<List<ItemRecepcion>> itemsDelAlmacen(String almacenId);
  Future<List<Proveedor>> proveedores();
  Future<Proveedor> crearProveedor(String nombre);

  /// SENASAG conocido para ese producto y proveedor, o null.
  Future<String?> senasacDe(int itemId, int proveedorId);

  Future<void> crearRecepcion(RecepcionNueva recepcion);

  /// Sube la foto al bucket privado y devuelve su ruta.
  Future<String> subirFoto(Uint8List bytes, {required String ruta, required String contentType});

  /// Enlace temporal para ver una foto guardada.
  Future<String> urlFoto(String ruta);

  Future<List<DiferenciaMes>> diferenciasDelMes(String almacenId, DateTime mes);
}

class SupabaseRecepcionesRepository implements RecepcionesRepository {
  static const _bucket = 'recepciones';

  SupabaseClient get _db => SupabaseService.client;

  @override
  Future<List<AlmacenRec>> almacenes() async {
    final filas = await _db
        .from('inv_almacenes')
        .select()
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) AlmacenRec.fromMap(f)];
  }

  @override
  Future<List<RecepcionDetalle>> recepciones(String almacenId, {int limite = 200}) async {
    final filas = await _db
        .from('inv_recepciones_detalle')
        .select()
        .eq('almacen_id', almacenId)
        .order('fecha', ascending: false)
        .order('id', ascending: false)
        .limit(limite)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) RecepcionDetalle.fromMap(f)];
  }

  @override
  Future<List<ItemRecepcion>> itemsDelAlmacen(String almacenId) async {
    final filas = await _db
        .from('inv_items')
        .select('id, codigo, detalle, unidad, inv_categorias!inner(almacen_id)')
        .eq('activo', true)
        .eq('inv_categorias.almacen_id', almacenId)
        .order('detalle')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) ItemRecepcion.fromMap(f)];
  }

  @override
  Future<List<Proveedor>> proveedores() async {
    final filas = await _db
        .from('inv_proveedores')
        .select()
        .eq('activo', true)
        .order('nombre')
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) Proveedor.fromMap(f)];
  }

  @override
  Future<Proveedor> crearProveedor(String nombre) async {
    final fila = await _db
        .from('inv_proveedores')
        .insert({'nombre': nombre})
        .select()
        .single()
        .timeout(SupabaseService.timeoutRed);
    return Proveedor.fromMap(fila);
  }

  @override
  Future<String?> senasacDe(int itemId, int proveedorId) async {
    final fila = await _db
        .from('inv_item_proveedor')
        .select('senasac')
        .eq('item_id', itemId)
        .eq('proveedor_id', proveedorId)
        .maybeSingle()
        .timeout(SupabaseService.timeoutRed);
    return fila?['senasac'] as String?;
  }

  @override
  Future<void> crearRecepcion(RecepcionNueva recepcion) async {
    await _db
        .from('inv_recepciones')
        .insert(recepcion.toMap())
        .timeout(SupabaseService.timeoutRed);
  }

  @override
  Future<String> subirFoto(Uint8List bytes,
      {required String ruta, required String contentType}) async {
    await _db.storage
        .from(_bucket)
        .uploadBinary(ruta, bytes, fileOptions: FileOptions(contentType: contentType))
        .timeout(const Duration(seconds: 60));
    return ruta;
  }

  @override
  Future<String> urlFoto(String ruta) => _db.storage.from(_bucket).createSignedUrl(ruta, 3600);

  @override
  Future<List<DiferenciaMes>> diferenciasDelMes(String almacenId, DateTime mes) async {
    final primero = DateTime(mes.year, mes.month, 1).toIso8601String().substring(0, 10);
    final filas = await _db
        .from('inv_diferencias_mes')
        .select()
        .eq('almacen_id', almacenId)
        .eq('mes', primero)
        .order('diferencia', ascending: true)
        .timeout(SupabaseService.timeoutRed);
    return [for (final f in filas) DiferenciaMes.fromMap(f)];
  }
}
