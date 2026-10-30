import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

/// Si alguien sale de la app SIN cerrar sesión, después de un rato hay que
/// volver a ingresar (en la fábrica las compus son compartidas: que el que
/// llega no siga trabajando a nombre del anterior).
///
/// Se anota la última vez que la app estuvo en uso (cada minuto mientras está
/// abierta, y al dejarla en segundo plano); al abrirla o volver a ella, si
/// pasó más de [limite], se cierra la sesión. Lo registrado no se pierde: la
/// cola sin conexión es por usuario y se sube cuando esa persona vuelve a
/// entrar (con o sin internet, ver `SesionOffline`).
class SesionInactividad {
  /// Cuánto puede estar la app sin usarse antes de pedir el ingreso otra vez.
  static const limite = Duration(hours: 1);

  static const _clave = 'ultima_actividad';
  static Box get _box => Hive.box(HiveBoxes.sesion);

  static Future<void> registrarActividad({DateTime? ahora}) =>
      _box.put(_clave, (ahora ?? DateTime.now()).toIso8601String());

  /// Sin registro (ej. primera vez después de actualizar la app) no se da
  /// por vencida: no se echa a nadie por un dato que no existía.
  static bool vencida({DateTime? ahora}) {
    final ultima = DateTime.tryParse(_box.get(_clave) as String? ?? '');
    if (ultima == null) return false;
    return (ahora ?? DateTime.now()).difference(ultima) > limite;
  }

  /// Corto, como en las apps de banco ("Tu sesión expiró"): sin él, que pida la
  /// contraseña de golpe parece una falla.
  static String get mensaje => 'Tu sesión se cerró por inactividad. Lo registrado sigue guardado.';
}
