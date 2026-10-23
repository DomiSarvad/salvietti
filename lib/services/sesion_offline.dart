import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

/// Ingreso sin internet.
///
/// Cada vez que alguien entra CON internet (Supabase verificó la contraseña),
/// se guarda en esta compu una huella de su contraseña — PBKDF2-SHA256 con sal
/// propia, nunca la contraseña — junto con su perfil y sus permisos. Sin
/// internet, el ingreso compara lo escrito contra esa huella.
///
/// Límites a propósito:
///  - Solo puede entrar sin internet quien ya entró con internet en ESTA compu
///    en los últimos [vigencia] días (si el Gerente lo desactivó o le cambió la
///    contraseña, se entera la próxima vez que haya conexión).
///  - 5 contraseñas mal seguidas bloquean el ingreso sin internet de ese correo
///    por [bloqueo] (el bloqueo del servidor, v23, no alcanza sin conexión).
class SesionOffline {
  static const vigencia = Duration(days: 30);
  static const bloqueo = Duration(minutes: 5);
  static const _maxFallos = 5;
  static const _iteraciones = 20000;

  static Box get _box => Hive.box(HiveBoxes.sesion);
  static String _clave(String correo) => 'offline_${correo.trim().toLowerCase()}';

  /// Después de un ingreso CON internet.
  static Future<void> recordar({
    required String correo,
    required String password,
    required Map<String, dynamic> perfil,
    required Set<String>? permisos,
    bool? datosCompletos,
  }) async {
    final sal = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    await _box.put(_clave(correo), {
      'sal': base64Encode(sal),
      'huella': base64Encode(_pbkdf2(utf8.encode(password), sal, _iteraciones)),
      'iteraciones': _iteraciones,
      'perfil': jsonEncode(perfil),
      'permisos': permisos?.toList(),
      // ¿Ya cargó sus datos personales obligatorios? (null = no se sabe)
      'datosCompletos': datosCompletos,
      'guardadoEn': DateTime.now().toIso8601String(),
      'fallos': 0,
    });
  }

  /// Verifica sin internet. Devuelve el perfil y los permisos guardados, o
  /// lanza [ErrorSesionOffline] con un mensaje para mostrar.
  static Future<({Map<String, dynamic> perfil, Set<String>? permisos, bool? datosCompletos})> verificar(
      String correo, String password,
      {DateTime Function()? ahora}) async {
    final hoy = (ahora ?? DateTime.now)();
    final k = _clave(correo);
    final v = _box.get(k);
    if (v is! Map) {
      throw const ErrorSesionOffline(
          'No hay internet, y esta cuenta todavía no entró nunca en esta compu con conexión. '
          'Para poder entrar sin internet, hay que haber entrado acá al menos una vez con internet.');
    }
    final datos = Map<String, dynamic>.from(v);
    final hasta = DateTime.tryParse(datos['bloqueadoHasta'] as String? ?? '');
    if (hasta != null && hoy.isBefore(hasta)) {
      final min = hasta.difference(hoy).inMinutes + 1;
      throw ErrorSesionOffline(
          'Demasiadas contraseñas incorrectas. Esperá $min minuto${min == 1 ? '' : 's'} o conectate a internet.');
    }
    final guardado = DateTime.parse(datos['guardadoEn'] as String);
    if (hoy.difference(guardado) > vigencia) {
      throw const ErrorSesionOffline(
          'Hace más de 30 días que esta cuenta no entra con internet en esta compu. '
          'Por seguridad, la próxima vez hay que entrar con conexión.');
    }

    final huella = _pbkdf2(utf8.encode(password), base64Decode(datos['sal'] as String),
        datos['iteraciones'] as int);
    if (!_iguales(huella, base64Decode(datos['huella'] as String))) {
      final fallos = ((datos['fallos'] as int?) ?? 0) + 1;
      datos['fallos'] = fallos;
      if (fallos >= _maxFallos) {
        datos['fallos'] = 0;
        datos['bloqueadoHasta'] = hoy.add(bloqueo).toIso8601String();
      }
      await _box.put(k, datos);
      throw const ErrorSesionOffline('Correo o contraseña incorrectos.');
    }

    if (datos['fallos'] != 0 || datos['bloqueadoHasta'] != null) {
      datos['fallos'] = 0;
      datos.remove('bloqueadoHasta');
      await _box.put(k, datos);
    }
    final perfil = Map<String, dynamic>.from(jsonDecode(datos['perfil'] as String) as Map);
    final lista = datos['permisos'] as List?;
    return (
      perfil: perfil,
      permisos: lista?.cast<String>().toSet(),
      datosCompletos: datos['datosCompletos'] as bool?,
    );
  }

  /// Completó sus datos personales (aunque sea sin internet: se suben con la
  /// cola). Así el próximo ingreso sin internet no se los vuelve a pedir.
  static Future<void> marcarDatosCompletos(String usuarioId) async {
    for (final k in _box.keys.toList()) {
      final v = _box.get(k);
      if (v is! Map || v['perfil'] == null) continue;
      final perfil = jsonDecode(v['perfil'] as String) as Map;
      if (perfil['id'] == usuarioId) {
        await _box.put(k, {...Map<String, dynamic>.from(v), 'datosCompletos': true});
      }
    }
  }

  /// Perfil guardado de un usuario por su id (para reabrir la app sin
  /// internet con una sesión que ya estaba abierta).
  static ({Map<String, dynamic> perfil, Set<String>? permisos, bool? datosCompletos})? perfilDe(
      String usuarioId) {
    for (final v in _box.values) {
      if (v is! Map || v['perfil'] == null) continue;
      final perfil = Map<String, dynamic>.from(jsonDecode(v['perfil'] as String) as Map);
      if (perfil['id'] == usuarioId) {
        return (
          perfil: perfil,
          permisos: (v['permisos'] as List?)?.cast<String>().toSet(),
          datosCompletos: v['datosCompletos'] as bool?,
        );
      }
    }
    return null;
  }

  /// PBKDF2-HMAC-SHA256, un bloque de 32 bytes (alcanza para una huella).
  static List<int> _pbkdf2(List<int> password, List<int> sal, int iteraciones) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...sal, 0, 0, 0, 1]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iteraciones; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  /// Comparación en tiempo constante.
  static bool _iguales(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }
}

class ErrorSesionOffline implements Exception {
  final String mensaje;
  const ErrorSesionOffline(this.mensaje);
  @override
  String toString() => mensaje;
}
