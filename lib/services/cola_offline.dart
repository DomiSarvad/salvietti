import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

/// Una escritura hecha sin internet, guardada en la compu hasta poder
/// subirla. Es el pedido HTTP tal cual lo armó Supabase (método, URL,
/// cuerpo), sin el token: al subirla se usa el token vigente en ese momento.
class OperacionOffline {
  final int clave; // orden de llegada (Hive.add): define el orden de subida
  final String metodo;
  final String url;
  final Map<String, String> headers;
  final Uint8List cuerpo;
  final String usuario; // id (sub del JWT) de quien la hizo
  final int? idTemporal; // id provisorio devuelto a la app mientras no suba
  final String descripcion;
  final DateTime creadoEn;
  final String? error; // solo en las que el servidor rechazó

  const OperacionOffline({
    required this.clave,
    required this.metodo,
    required this.url,
    required this.headers,
    required this.cuerpo,
    required this.usuario,
    required this.idTemporal,
    required this.descripcion,
    required this.creadoEn,
    this.error,
  });

  factory OperacionOffline.fromMap(int clave, Map m) => OperacionOffline(
        clave: clave,
        metodo: m['metodo'] as String,
        url: m['url'] as String,
        headers: Map<String, String>.from(m['headers'] as Map),
        cuerpo: m['cuerpo'] as Uint8List,
        usuario: m['usuario'] as String,
        idTemporal: m['idTemporal'] as int?,
        descripcion: m['descripcion'] as String,
        creadoEn: DateTime.parse(m['creadoEn'] as String),
        error: m['error'] as String?,
      );

  Map<String, dynamic> toMap({String? error}) => {
        'metodo': metodo,
        'url': url,
        'headers': headers,
        'cuerpo': cuerpo,
        'usuario': usuario,
        'idTemporal': idTemporal,
        'descripcion': descripcion,
        'creadoEn': creadoEn.toIso8601String(),
        'error': error ?? this.error,
      };
}

/// Persistencia local del modo sin conexión de los módulos nuevos
/// (`lib/features/`), en Hive — igual que la cola legacy de `movimientos`
/// (`HiveService`), pero genérica: guarda pedidos HTTP, no un modelo puntual.
///
///  - **Caché de lecturas**: la última respuesta buena de cada consulta, por
///    usuario, para poder mostrar los datos sin internet.
///  - **Cola**: las escrituras hechas sin internet, en orden de llegada.
///  - **Con error**: las que al subir el servidor rechazó (ej. ya no alcanza
///    el stock); quedan a la vista para reintentar o descartar, no se pierden.
///  - **Ids temporales**: cuando una escritura sin internet "crea" algo (una
///    corrida, un preparado), la app recibe un id provisorio negativo; al
///    subirla se anota el id real, y cualquier operación posterior que use
///    el provisorio (ej. finalizar esa corrida) se sube ya con el real.
class ColaOffline {
  /// Cambia cada vez que cambia la cola o los errores (para refrescar la UI).
  static final cambios = ValueNotifier<int>(0);

  static const _maxCache = 800;

  /// Base de los ids provisorios: negativos y de 12 cifras, imposibles de
  /// confundir con un id real (que son positivos) ni con otro número del
  /// cuerpo de un pedido.
  static const _baseIdTemporal = 900000000000;
  static final patronIdTemporal = RegExp(r'(?<![0-9])-9\d{11}(?![0-9])');

  static Box get _cache => Hive.box(HiveBoxes.cacheLecturas);
  static Box get _cola => Hive.box(HiveBoxes.colaOffline);
  static Box get _errores => Hive.box(HiveBoxes.erroresOffline);
  static Box get _ids => Hive.box(HiveBoxes.idsTemporales);

  static Future<void> init() async {
    await Hive.openBox(HiveBoxes.cacheLecturas);
    await Hive.openBox(HiveBoxes.colaOffline);
    await Hive.openBox(HiveBoxes.erroresOffline);
    await Hive.openBox(HiveBoxes.idsTemporales);
  }

  // -------------------- Caché de lecturas --------------------

  /// Las claves de Hive tienen un máximo de 255 caracteres y una URL de
  /// PostgREST con su `select=` lo supera seguido: se guarda bajo un hash,
  /// con la clave completa adentro para descartar una colisión.
  static String _hash(String s) {
    var a = 0x811c9dc5, b = 0x01000193;
    for (final c in utf8.encode(s)) {
      a = ((a ^ c) * 0x01000193) & 0xffffffff;
      b = ((b ^ c) * 0x0100019d + 7) & 0xffffffff;
    }
    return '${a.toRadixString(16)}${b.toRadixString(16)}_${s.length}';
  }

  static Map? leerCache(String clave) {
    final v = _cache.get(_hash(clave));
    if (v is! Map || v['clave'] != clave) return null;
    return v;
  }

  static Future<void> guardarCache(
      String clave, int status, Map<String, String> headers, Uint8List cuerpo) async {
    await _cache.put(_hash(clave), {
      'clave': clave,
      'status': status,
      'headers': headers,
      'cuerpo': cuerpo,
      'fecha': DateTime.now().toIso8601String(),
    });
    if (_cache.length > _maxCache) await _podarCache();
  }

  /// Borra las consultas más viejas (ej. búsquedas que no se repiten).
  static Future<void> _podarCache() async {
    final entradas = _cache.toMap().entries.toList()
      ..sort((x, y) =>
          ((x.value as Map)['fecha'] as String).compareTo((y.value as Map)['fecha'] as String));
    final sobran = entradas.length - (_maxCache * 3 ~/ 4);
    await _cache.deleteAll([for (final e in entradas.take(sobran)) e.key]);
  }

  // -------------------- Cola de escrituras --------------------

  static Future<int> nuevoIdTemporal() async {
    final n = ((_ids.get('_contador') as int?) ?? 0) + 1;
    await _ids.put('_contador', n);
    return -(_baseIdTemporal + n);
  }

  static Future<void> encolar(Map<String, dynamic> operacion) async {
    await _cola.add(operacion);
    cambios.value++;
  }

  static List<OperacionOffline> _leer(Box box) {
    final m = box.toMap();
    final claves = m.keys.cast<int>().toList()..sort();
    return [for (final k in claves) OperacionOffline.fromMap(k, m[k] as Map)];
  }

  static List<OperacionOffline> pendientes() => _leer(_cola);
  static List<OperacionOffline> conError() => _leer(_errores);
  static int get cantidadPendientes => _cola.length;
  static int get cantidadConError => _errores.length;

  static bool hayPendientesDe(String usuario) =>
      _cola.values.any((v) => (v as Map)['usuario'] == usuario);

  static Future<void> quitar(OperacionOffline op) async {
    await _cola.delete(op.clave);
    cambios.value++;
  }

  /// El servidor la rechazó: sale de la cola (para no trabar las demás) y
  /// queda en la lista de errores con el motivo.
  static Future<void> marcarError(OperacionOffline op, String motivo) async {
    await _errores.add(op.toMap(error: motivo));
    await _cola.delete(op.clave);
    cambios.value++;
  }

  /// La vuelve a poner al final de la cola, sin el error.
  static Future<void> reintentar(OperacionOffline op) async {
    await _cola.add(op.toMap()..['error'] = null);
    await _errores.delete(op.clave);
    cambios.value++;
  }

  static Future<void> descartar(OperacionOffline op) async {
    await _errores.delete(op.clave);
    cambios.value++;
  }

  // -------------------- Ids temporales --------------------

  static Future<void> anotarIdReal(int temporal, int real) =>
      _ids.put(temporal.toString(), real);

  /// Reemplaza cada id provisorio que ya tenga id real.
  static String resolverIds(String texto) => texto.replaceAllMapped(patronIdTemporal, (m) {
        final real = _ids.get(m[0]);
        return real == null ? m[0]! : real.toString();
      });
}
