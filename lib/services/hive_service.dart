import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../models/movimiento.dart';
import 'cola_offline.dart';

/// Capa de persistencia local. Funciona en móvil, escritorio Y web
/// (Hive usa IndexedDB por debajo en web), cumpliendo el requisito de
/// "una sola base de código para teléfonos y computadoras".
///
/// Estrategia offline-first:
///  - El catálogo (tapas/preformas/materia_prima) se cachea localmente
///    cada vez que se lee con éxito de Supabase, para poder consultarlo
///    sin conexión.
///  - Los movimientos registrados sin conexión se guardan en la
///    "cola de sincronización" (colaMovimientos) y quedan marcados
///    como pendientes hasta que el usuario presiona "Subir todo" (o el
///    sistema detecta conexión y sincroniza automáticamente).
class HiveService {
  static Future<void> init() async {
    await Hive.initFlutter();
    await abrirCajas();
  }

  /// Abre todas las cajas que usa la app. Separado de [init] para los tests,
  /// que inicializan Hive en una carpeta temporal (`Hive.init(ruta)`) en vez
  /// de la carpeta del dispositivo (`initFlutter` necesita un plugin).
  static Future<void> abrirCajas() async {
    await Hive.openBox(HiveBoxes.tapas);
    await Hive.openBox(HiveBoxes.preformas);
    await Hive.openBox(HiveBoxes.materiaPrima);
    await Hive.openBox(HiveBoxes.colaMovimientos);
    await Hive.openBox(HiveBoxes.sesion);
    await Hive.openBox(HiveBoxes.perfilPendiente);
    await Hive.openBox(HiveBoxes.preferencias);
    await ColaOffline.init();
  }

  static Box _boxCatalogo(String tabla) {
    switch (tabla) {
      case 'tapas':
        return Hive.box(HiveBoxes.tapas);
      case 'preformas':
        return Hive.box(HiveBoxes.preformas);
      case 'materia_prima':
        return Hive.box(HiveBoxes.materiaPrima);
      default:
        throw ArgumentError('Tabla desconocida: $tabla');
    }
  }

  /// Reemplaza el caché local completo de una tabla con los datos frescos
  /// del servidor (se llama tras cada lectura exitosa online).
  static Future<void> guardarCatalogo(
      String tabla, List<Map<String, dynamic>> filas) async {
    final box = _boxCatalogo(tabla);
    await box.clear();
    for (final f in filas) {
      await box.put(f['id'], f);
    }
  }

  static List<Map<String, dynamic>> leerCatalogo(String tabla) {
    final box = _boxCatalogo(tabla);
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // -------------------- Cola de movimientos pendientes --------------------

  static Future<void> encolarMovimiento(Movimiento m) async {
    final box = Hive.box(HiveBoxes.colaMovimientos);
    await box.put(m.offlineUuid, m.toHiveMap());
  }

  static List<Movimiento> movimientosPendientes() {
    final box = Hive.box(HiveBoxes.colaMovimientos);
    return box.values
        .map((e) => Movimiento.fromHiveMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static int get cantidadPendientes =>
      Hive.box(HiveBoxes.colaMovimientos).length;

  static Future<void> quitarDeCola(String offlineUuid) async {
    await Hive.box(HiveBoxes.colaMovimientos).delete(offlineUuid);
  }

  // -------------------- Sesión (para recordar último usuario) -------------

  static Future<void> guardarUltimoEmail(String email) async {
    await Hive.box(HiveBoxes.sesion).put('ultimo_email', email);
  }

  static String? ultimoEmail() =>
      Hive.box(HiveBoxes.sesion).get('ultimo_email');

  // -------------------- Foto de perfil pendiente de subir ------------------

  static Future<void> guardarFotoPendiente(
      String usuarioId, Uint8List bytes, String ext) async {
    await Hive.box(HiveBoxes.perfilPendiente)
        .put('foto', {'usuarioId': usuarioId, 'bytes': bytes, 'ext': ext});
  }

  static Map<String, dynamic>? fotoPendiente() {
    final valor = Hive.box(HiveBoxes.perfilPendiente).get('foto');
    return valor == null ? null : Map<String, dynamic>.from(valor);
  }

  static Future<void> limpiarFotoPendiente() async {
    await Hive.box(HiveBoxes.perfilPendiente).delete('foto');
  }

  static bool get hayFotoPendiente =>
      Hive.box(HiveBoxes.perfilPendiente).containsKey('foto');
}
