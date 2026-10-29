import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'cola_offline.dart';
import 'http_base.dart';

/// Resultado de subir la cola de escrituras hechas sin internet.
class ResultadoSubida {
  final int subidas;
  final int rechazadas;
  final bool cortadoPorRed; // se cortó la conexión a mitad de camino
  const ResultadoSubida(this.subidas, this.rechazadas, this.cortadoPorRed);
}

/// Cliente HTTP que usa Supabase por debajo (`Supabase.initialize(httpClient:)`),
/// para que TODOS los módulos funcionen sin internet sin tener que tocar cada
/// repositorio:
///
///  - **Lecturas** (GET a `/rest/v1/` y las RPC de solo lectura): cada
///    respuesta buena se guarda en la compu; sin internet se devuelve esa
///    copia (los datos de la última vez que se vieron con conexión).
///  - **Escrituras** (insert/update/delete y RPC que registran algo): sin
///    internet se encolan en Hive (`ColaOffline`) y a la app se le contesta
///    como si hubieran salido bien — si la RPC devuelve un id (iniciar una
///    corrida, un preparado), se le da uno provisorio. `SyncService` las sube
///    en el mismo orden apenas vuelve la conexión, y ahí el servidor aplica
///    todas sus reglas (stock, permisos) como siempre: si alguna ya no
///    corresponde, queda en "con error" a la vista, no se pierde.
///
/// Lo que exige estar en línea (login, alta de usuarios, permisos, la clave
/// del Gerente) pasa directo y falla como antes. La cola legacy de
/// `movimientos` (`HiveService`) y la foto de perfil tampoco pasan por acá:
/// ya tenían su propio mecanismo offline.
class ClienteOffline extends http.BaseClient {
  ClienteOffline([http.Client? interno]) : _interno = interno ?? crearClienteHttp();
  final http.Client _interno;

  /// Una escritura que falla por red DESPUÉS de esto no se encola: las
  /// pantallas esperan 8 s (`SupabaseService.timeoutRed`) y, pasado ese
  /// tiempo, ya le mostraron a la persona "no se pudo". Si se encolara igual,
  /// se subiría sola más tarde, y si la persona lo volvió a intentar (lo
  /// normal después de ver un error) quedaría registrado dos veces. Con
  /// esto, lo que ve la persona y lo que pasa coinciden: o "se guardó en esta
  /// compu" (y se sube), o un error (y no se hizo nada).
  @visibleForTesting
  static Duration limiteParaEncolar = const Duration(seconds: 7);

  /// Si el último pedido llegó al servidor. Lo actualiza cada respuesta (o
  /// falla de red); más confiable que connectivity_plus, que dice "wifi"
  /// aunque el wifi no tenga salida a internet.
  static final hayRed = ValueNotifier<bool>(true);

  /// connectivity_plus informa que no hay ninguna red: no tiene sentido ni
  /// intentar, la escritura va directo a la cola. Lo setea `SyncService`.
  static bool sinInterfaz = false;

  /// Avisa (con la descripción) cada escritura que se guardó en la compu.
  static final _guardadas = StreamController<String>.broadcast();
  static Stream<String> get alGuardarSinRed => _guardadas.stream;

  /// Lecturas: con copia guardada, no se espera más que esto a la red antes
  /// de mostrar la copia (con wifi sin salida un pedido puede colgarse hasta
  /// el `timeoutRed` de 8 s de los repositorios, que sin esto ganaría).
  static const _esperaConCopia = Duration(seconds: 5);

  /// Catálogos que casi no cambian y que muchas pantallas piden PRIMERO, antes
  /// de pedir lo demás (ej. la lista de almacenes): se guardan en memoria unos
  /// minutos, así entrar a Almacenes, Recepciones o el Inicio no espera ese
  /// viaje al servidor cada vez. Cualquier escritura los borra de la memoria
  /// (una RPC puede tocar cualquier tabla: borra todo), así lo que uno cambia se
  /// ve al toque; lo que cambia OTRA persona tarda hasta [_vidaMemoria].
  static const _catalogos = {
    'inv_almacenes',
    'inv_categorias',
    'sabores',
    'presentaciones',
    'sabor_presentacion',
    'app_modulos',
  };
  static const _vidaMemoria = Duration(minutes: 2);
  static final _memoria = <String, ({DateTime en, String tabla, http.Response r})>{};

  /// Vacía la memoria de catálogos (al cerrar sesión, y en los tests).
  static void olvidarMemoria() => _memoria.clear();

  static String? _tablaDeLectura(http.BaseRequest r) {
    if (r.method.toUpperCase() != 'GET') return null;
    final rest = _despues(r.url.pathSegments, 'rest', 'v1');
    if (rest == null || rest.isEmpty || rest.first == 'rpc') return null;
    return rest.first;
  }

  static void _olvidarPorEscritura(http.BaseRequest r) {
    final rest = _despues(r.url.pathSegments, 'rest', 'v1');
    if (rest == null || rest.isEmpty) return;
    if (rest.first == 'rpc') {
      _memoria.clear();
    } else {
      _memoria.removeWhere((_, v) => v.tabla == rest.first);
    }
  }

  // RPC que solo consultan: se cachean como un GET, nunca se encolan.
  static const _rpcLectura = {
    'jarabes_verificar_insumos',
    'usuarios_con_correo',
    'intentos_login_bloqueadas',
    'presencia_listar',
  };

  // Necesitan respuesta real del servidor en el momento: pasan directo.
  static const _rpcSoloEnLinea = {
    'intentos_login_estado',
    'intentos_login_registrar_fallo',
    'intentos_login_registrar_exito',
    'intentos_login_desbloquear',
    'crear_usuario_admin',
    'editar_usuario_admin',
    'jarabes_receta_confirmar_gerente', // vuelve a pedir la contraseña
    'presencia_latido', // un "sigo acá" de hace una hora no sirve: nunca a la cola
    'presencia_salir',
  };

  static const _tablasSoloEnLinea = {
    'movimientos', // legacy: tiene su propia cola (HiveService)
    'permisos_rol', // Permisos guarda casilla por casilla y deshace si falla
    'tours_vistos', // sin red alcanza con lo recordado en la compu
  };

  static const _bucketsSoloEnLinea = {
    'avatars', // AuthService ya la deja pendiente
    'productos', // la foto de un producto se elige de nuevo si no hay red
    'items', // ídem, la foto de un ítem del inventario
  };

  // Rutas de Storage que no son subir un archivo.
  static const _rutasStorageNoSubida = {
    'sign', 'list', 'public', 'info', 'move', 'copy', 'authenticated', 'upload',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    switch (_clasificar(request)) {
      case _Tipo.lectura:
        return _leer(request);
      case _Tipo.escritura:
        return _escribir(request);
      case _Tipo.directo:
        return _directo(request);
    }
  }

  @override
  void close() => _interno.close();

  // -------------------- Clasificación --------------------

  static _Tipo _clasificar(http.BaseRequest r) {
    final seg = r.url.pathSegments;
    final metodo = r.method.toUpperCase();
    final rest = _despues(seg, 'rest', 'v1');
    if (rest != null && rest.isNotEmpty) {
      if (rest.first == 'rpc' && rest.length > 1) {
        final funcion = rest[1];
        if (_rpcLectura.contains(funcion)) return _Tipo.lectura;
        if (_rpcSoloEnLinea.contains(funcion)) return _Tipo.directo;
        return metodo == 'GET' ? _Tipo.lectura : _Tipo.escritura;
      }
      if (metodo == 'GET' || metodo == 'HEAD') return _Tipo.lectura;
      if (_tablasSoloEnLinea.contains(rest.first)) return _Tipo.directo;
      return _Tipo.escritura;
    }
    final storage = _despues(seg, 'storage', 'v1');
    if (storage != null &&
        storage.length > 2 &&
        storage.first == 'object' &&
        (metodo == 'POST' || metodo == 'PUT') &&
        !_rutasStorageNoSubida.contains(storage[1]) &&
        !_bucketsSoloEnLinea.contains(storage[1])) {
      return _Tipo.escritura;
    }
    return _Tipo.directo; // auth, realtime, el resto de storage
  }

  static List<String>? _despues(List<String> seg, String a, String b) {
    for (var i = 0; i + 1 < seg.length; i++) {
      if (seg[i] == a && seg[i + 1] == b) return seg.sublist(i + 2);
    }
    return null;
  }

  // -------------------- Detección de falta de red --------------------

  /// La falla es de conexión (no un error del servidor).
  static bool esFallaDeRed(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString();
    return e is http.ClientException ||
        s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('Failed host lookup');
  }

  /// La falla pudo haber pasado DESPUÉS de que el servidor recibió el pedido
  /// (se cortó esperando la respuesta): encolarlo podría registrarlo dos
  /// veces, así que en ese caso se informa el error como antes y la persona
  /// decide si reintentar.
  static bool _ambigua(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('broken pipe');
  }

  static void _marcarRed(bool hay) {
    if (hayRed.value != hay) hayRed.value = hay;
  }

  Future<http.StreamedResponse> _directo(http.BaseRequest request) async {
    try {
      final r = await _interno.send(request);
      _marcarRed(true);
      return r;
    } catch (e) {
      if (esFallaDeRed(e)) _marcarRed(false);
      rethrow;
    }
  }

  // -------------------- Lecturas --------------------

  Future<http.StreamedResponse> _leer(http.BaseRequest request) async {
    final cuerpo = await request.finalize().toBytes();
    final clave =
        '${usuarioDe(request.headers)}|${request.method}|${request.url}|${utf8.decode(cuerpo, allowMalformed: true)}';

    final tabla = _tablaDeLectura(request);
    final enMemoria = _memoria[clave];
    if (enMemoria != null && DateTime.now().difference(enMemoria.en) < _vidaMemoria) {
      final r = enMemoria.r;
      return _aStreamed(r.statusCode, r.headers, r.bodyBytes, request);
    }

    // El pedido sale ya; la copia del disco se lee mientras tanto.
    final red = _interno.send(_copiar(request, cuerpo)).then((r) async {
      final resp = await http.Response.fromStream(r);
      if (tabla != null && _catalogos.contains(tabla) && resp.statusCode == 200) {
        _memoria[clave] = (en: DateTime.now(), tabla: tabla, r: resp);
      }
      return resp;
    });
    // Si la red falla mientras se lee el disco, que no quede como error "sin
    // atender": quien espera `red` más abajo lo recibe igual.
    unawaited(red.then((_) {}, onError: (_) {}));
    final copia = await ColaOffline.leerCache(clave);

    if (copia == null) {
      try {
        final r = await red;
        _marcarRed(true);
        // Se guarda en segundo plano: la pantalla no espera al disco.
        unawaited(_guardarSiCorresponde(clave, r));
        return _aStreamed(r.statusCode, r.headers, r.bodyBytes, request);
      } catch (e) {
        if (esFallaDeRed(e)) _marcarRed(false);
        rethrow; // sin red y sin copia: el error de siempre
      }
    }

    final resultado = Completer<http.StreamedResponse>();
    void usarCopia() {
      if (resultado.isCompleted) return;
      resultado.complete(_aStreamed(copia['status'] as int,
          Map<String, String>.from(copia['headers'] as Map), copia['cuerpo'] as Uint8List, request));
    }

    final espera = Timer(_esperaConCopia, usarCopia);
    red.then((r) async {
      _marcarRed(true);
      unawaited(_guardarSiCorresponde(clave, r));
      espera.cancel();
      if (!resultado.isCompleted) {
        resultado.complete(_aStreamed(r.statusCode, r.headers, r.bodyBytes, request));
      }
    }, onError: (Object e, StackTrace st) {
      espera.cancel();
      if (esFallaDeRed(e)) {
        _marcarRed(false);
        usarCopia();
      } else if (!resultado.isCompleted) {
        resultado.completeError(e, st);
      }
    });
    return resultado.future;
  }

  static Future<void> _guardarSiCorresponde(String clave, http.Response r) async {
    if (r.statusCode < 200 || r.statusCode >= 300) return;
    final h = <String, String>{
      for (final k in const ['content-type', 'content-range'])
        if (r.headers[k] != null) k: r.headers[k]!,
    };
    try {
      await ColaOffline.guardarCache(clave, r.statusCode, h, r.bodyBytes);
    } catch (_) {
      // Sin espacio en disco, etc.: no impide mostrar la respuesta.
    }
  }

  // -------------------- Escrituras --------------------

  Future<http.StreamedResponse> _escribir(http.BaseRequest request) async {
    final cuerpo = await request.finalize().toBytes();
    final usuario = usuarioDe(request.headers);
    _olvidarPorEscritura(request);

    // Si ya hay algo pendiente de esta persona, lo nuevo va detrás (el orden
    // importa: finalizar una corrida va después de iniciarla). Lo mismo si
    // usa un id provisorio, que solo se resuelve al subir la cola.
    final alaCola = sinInterfaz ||
        ColaOffline.hayPendientesDe(usuario) ||
        ColaOffline.patronIdTemporal.hasMatch(request.url.toString()) ||
        (_esJson(request.headers) &&
            ColaOffline.patronIdTemporal.hasMatch(utf8.decode(cuerpo, allowMalformed: true)));

    if (!alaCola) {
      final reloj = Stopwatch()..start();
      try {
        final r = await _interno.send(_copiar(request, cuerpo));
        _marcarRed(true);
        return r;
      } catch (e) {
        if (!esFallaDeRed(e) || _ambigua(e)) {
          if (esFallaDeRed(e)) _marcarRed(false);
          rethrow;
        }
        _marcarRed(false);
        if (reloj.elapsed >= limiteParaEncolar) rethrow; // la pantalla ya dio error
      }
    }
    return _encolar(request, cuerpo, usuario);
  }

  Future<http.StreamedResponse> _encolar(
      http.BaseRequest request, Uint8List cuerpo, String usuario) async {
    final seg = request.url.pathSegments;
    final rest = _despues(seg, 'rest', 'v1');
    final esRpc = rest != null && rest.first == 'rpc';
    final esInsert = rest != null && !esRpc && request.method.toUpperCase() == 'POST';
    final idTemporal = (esRpc || esInsert) ? await ColaOffline.nuevoIdTemporal() : null;

    final headers = Map<String, String>.from(request.headers)
      ..removeWhere((k, _) => k.toLowerCase() == 'authorization');
    final descripcion = describir(request.method, request.url);
    await ColaOffline.encolar({
      'metodo': request.method,
      'url': request.url.toString(),
      'headers': headers,
      'cuerpo': cuerpo,
      'usuario': usuario,
      'idTemporal': idTemporal,
      'descripcion': descripcion,
      'creadoEn': DateTime.now().toIso8601String(),
      'error': null,
    });
    _guardadas.add(descripcion);
    return _respuestaSimulada(request, cuerpo, idTemporal);
  }

  /// Lo que hubiera contestado el servidor, lo más parecido posible, para
  /// que el repositorio que hizo el pedido siga como si nada.
  static http.StreamedResponse _respuestaSimulada(
      http.BaseRequest request, Uint8List cuerpo, int? idTemporal) {
    const json = {'content-type': 'application/json; charset=utf-8'};
    final seg = request.url.pathSegments;
    final rest = _despues(seg, 'rest', 'v1');

    if (rest == null) {
      // Subida a Storage.
      final ruta = _despues(seg, 'storage', 'v1')!.skip(1).join('/');
      return _aStreamed(200, json, _bytes({'Key': ruta, 'Id': 'pendiente'}), request);
    }
    if (rest.first == 'rpc') {
      return _aStreamed(200, json, _bytes(idTemporal), request);
    }
    final prefer = request.headers['Prefer'] ?? request.headers['prefer'] ?? '';
    if (!prefer.contains('return=representation')) {
      return _aStreamed(request.method.toUpperCase() == 'POST' ? 201 : 204, json, Uint8List(0), request);
    }
    Object? filas;
    try {
      filas = jsonDecode(utf8.decode(cuerpo));
    } catch (_) {
      filas = const [];
    }
    List<dynamic> lista = filas is List ? [...filas] : [if (filas != null) filas];
    if (idTemporal != null && lista.length == 1 && lista.first is Map) {
      lista = [
        {...(lista.first as Map), if ((lista.first as Map)['id'] == null) 'id': idTemporal}
      ];
    }
    final accept = request.headers['Accept'] ?? request.headers['accept'] ?? '';
    final salida = accept.contains('vnd.pgrst.object') ? (lista.isEmpty ? null : lista.first) : lista;
    return _aStreamed(201, json, _bytes(salida), request);
  }

  // -------------------- Subida de la cola --------------------

  /// Sube, en orden, lo que [usuario] hizo sin internet. Se corta en la
  /// primera falla de red (lo que queda sigue en la cola); un rechazo del
  /// servidor no corta: esa operación pasa a "con error" y sigue con la
  /// próxima. [token] da el token vigente; [refrescarToken] lo renueva si el
  /// servidor dice que venció (estuvo mucho tiempo sin internet).
  static Future<ResultadoSubida> subirCola({
    required String usuario,
    required String? Function() token,
    required Future<void> Function() refrescarToken,
    @visibleForTesting http.Client? clienteHttp,
  }) async {
    final cliente = clienteHttp ?? crearClienteHttp();
    var subidas = 0, rechazadas = 0;
    try {
      for (final op in ColaOffline.pendientes().where((o) => o.usuario == usuario)) {
        final url = ColaOffline.resolverIds(op.url);
        var cuerpo = op.cuerpo;
        if (_esJson(op.headers)) {
          cuerpo = Uint8List.fromList(utf8.encode(ColaOffline.resolverIds(utf8.decode(cuerpo))));
        }
        if (ColaOffline.patronIdTemporal.hasMatch(url) ||
            (_esJson(op.headers) &&
                ColaOffline.patronIdTemporal.hasMatch(utf8.decode(cuerpo)))) {
          await ColaOffline.marcarError(op,
              'Depende de otra operación que el servidor rechazó (ver más arriba en esta lista).');
          rechazadas++;
          continue;
        }

        Future<http.Response> enviar() async {
          final req = http.Request(op.metodo, Uri.parse(url))
            ..headers.addAll(op.headers)
            ..headers['Authorization'] = 'Bearer ${token() ?? ''}'
            ..bodyBytes = cuerpo;
          return http.Response.fromStream(await cliente.send(req).timeout(const Duration(seconds: 30)));
        }

        http.Response r;
        try {
          r = await enviar();
          if (r.statusCode == 401) {
            await refrescarToken();
            r = await enviar();
          }
        } catch (e) {
          if (!esFallaDeRed(e)) rethrow;
          _marcarRed(false);
          if (_ambigua(e)) {
            // Pudo haber llegado: reenviarla sola podría registrarla dos
            // veces (ej. descontar stock dos veces). Que lo decida una persona.
            await ColaOffline.marcarError(op,
                'Se cortó la conexión mientras se subía y no se sabe si llegó. '
                'Fijate en su pantalla si ya figura antes de reintentar.');
            rechazadas++;
          }
          return ResultadoSubida(subidas, rechazadas, true);
        }
        _marcarRed(true);

        if (r.statusCode >= 200 && r.statusCode < 300) {
          final real = _idDeRespuesta(r.body);
          if (op.idTemporal != null && real != null) {
            await ColaOffline.anotarIdReal(op.idTemporal!, real);
          }
          await ColaOffline.quitar(op);
          subidas++;
        } else if (const {401, 408, 429, 502, 503, 504}.contains(r.statusCode)) {
          // Del servidor o de la sesión, no de la operación: se reintenta después.
          return ResultadoSubida(subidas, rechazadas, true);
        } else {
          await ColaOffline.marcarError(op, _mensajeDeError(r));
          rechazadas++;
        }
      }
      return ResultadoSubida(subidas, rechazadas, false);
    } finally {
      if (clienteHttp == null) cliente.close();
    }
  }

  static int? _idDeRespuesta(String body) {
    if (body.isEmpty) return null;
    try {
      var v = jsonDecode(body);
      if (v is List && v.isNotEmpty) v = v.first;
      if (v is Map) v = v['id'];
      return v is num ? v.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  static String _mensajeDeError(http.Response r) {
    try {
      final v = jsonDecode(r.body);
      if (v is Map && v['message'] != null) return v['message'].toString();
    } catch (_) {}
    return 'El servidor la rechazó (código ${r.statusCode}).';
  }

  // -------------------- Utilidades --------------------

  /// Id del usuario (`sub` del JWT) que hace el pedido; "anon" sin sesión.
  /// Quien entró SIN internet (`SesionOffline`): no tiene sesión de Supabase,
  /// así que sus pedidos van con la clave anónima. Con esto sus lecturas usan
  /// SU copia guardada y lo que registra queda en la cola a SU nombre (se sube
  /// cuando vuelve internet y `AuthService` reabre la sesión de verdad).
  static String? usuarioSinConexion;

  static String usuarioDe(Map<String, String> headers) {
    final auth = headers['Authorization'] ?? headers['authorization'] ?? '';
    final partes = auth.replaceFirst('Bearer ', '').split('.');
    String? sub;
    if (partes.length == 3) {
      try {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
        sub = payload is Map ? payload['sub'] as String? : null;
      } catch (_) {}
    }
    return sub ?? usuarioSinConexion ?? 'anon';
  }

  static bool _esJson(Map<String, String> headers) {
    final ct = headers['Content-Type'] ?? headers['content-type'] ?? '';
    return ct.contains('json');
  }

  static Uint8List _bytes(Object? v) => Uint8List.fromList(utf8.encode(jsonEncode(v)));

  static http.Request _copiar(http.BaseRequest original, Uint8List cuerpo) {
    final c = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    if (cuerpo.isNotEmpty) c.bodyBytes = cuerpo;
    return c;
  }

  static http.StreamedResponse _aStreamed(
          int status, Map<String, String> headers, Uint8List cuerpo, http.BaseRequest request) =>
      http.StreamedResponse(Stream.value(cuerpo), status,
          contentLength: cuerpo.length, request: request, headers: headers);

  // Nombres legibles para la lista de pendientes de Configuración.
  static const _nombres = {
    'soplado_iniciar_corrida': 'Soplado: iniciar corrida',
    'soplado_finalizar_corrida': 'Soplado: finalizar corrida',
    'soplado_anular_corrida': 'Soplado: anular corrida',
    'llenadora_iniciar_corrida': 'Llenadora: iniciar corrida',
    'llenadora_finalizar_corrida': 'Llenadora: finalizar corrida',
    'llenadora_anular_corrida': 'Llenadora: anular corrida',
    'codificacion_iniciar_corrida': 'Codificación: iniciar corrida',
    'codificacion_finalizar_corrida': 'Codificación: finalizar corrida',
    'codificacion_anular_corrida': 'Codificación: anular corrida',
    'jarabes_iniciar_preparado': 'Jarabes: iniciar preparado',
    'jarabes_finalizar_preparado': 'Jarabes: finalizar preparado',
    'jarabes_anular_preparado': 'Jarabes: anular preparado',
    'jarabes_receta_crear': 'Jarabes: proponer receta',
    'jarabes_receta_aprobar_calidad': 'Jarabes: aprobar receta (Calidad)',
    'jarabes_receta_aprobar_produccion': 'Jarabes: aprobar receta (Producción)',
    'jarabes_receta_rechazar': 'Jarabes: rechazar receta',
    'calidad_registrar_analisis': 'Calidad: registrar análisis',
    'calidad_actualizar_analisis': 'Calidad: actualizar análisis',
    'inv_crear_pedido': 'Pedido a Almacén',
    'inv_entregar_pedido': 'Entregas: entregar pedido',
    'inv_confirmar_entrega': 'Entregas: confirmar recepción',
    'inv_resolver_observacion': 'Entregas: resolver observación',
    'inv_anular_pedido': 'Entregas: anular pedido',
    'inv_registrar_devolucion': 'Entregas: devolución',
    'inv_registrar_movimiento': 'Almacenes: movimiento manual',
    'inv_revertir_movimiento': 'Almacenes: revertir movimiento',
    'inv_registrar_salida_directa': 'Almacenes: salida directa',
    'mermas_registrar': 'Mermas: registrar merma',
    'soda_registrar_entrega': 'Soda Cáustica: entrega',
    'salidas_crear_reporte': 'Registro de salidas: nuevo reporte',
    'salidas_guardar_linea': 'Registro de salidas: guardar línea',
    'salidas_eliminar_linea': 'Registro de salidas: borrar línea',
    'salidas_cerrar_reporte': 'Registro de salidas: cerrar reporte',
    'compras_crear_pedido': 'Pedidos de compra: nuevo pedido',
    'compras_resolver': 'Pedidos de compra: resolver',
    'compras_anular': 'Pedidos de compra: anular',
    'solicitud_crear': 'Solicitud a Gerencia',
    'solicitud_resolver': 'Solicitudes: resolver',
    'eliminar_logico': 'Eliminar registro',
    'inv_items': 'Almacenes: ítem',
    'inv_conteos': 'Almacenes: conteo',
    'inv_recepciones': 'Recepciones: nueva recepción',
    'inv_proveedores': 'Recepciones: nuevo proveedor',
    'bitacora_acciones': 'Bitácora',
    'plan_produccion': 'Producción del día: plan',
    'plan_produccion_detalle': 'Producción del día: producto',
  };

  static String describir(String metodo, Uri url) {
    final seg = url.pathSegments;
    final rest = _despues(seg, 'rest', 'v1');
    if (rest == null) return 'Subir archivo';
    final nombre = rest.first == 'rpc' && rest.length > 1 ? rest[1] : rest.first;
    final legible = _nombres[nombre] ?? nombre.replaceAll('_', ' ');
    if (rest.first == 'rpc') return legible;
    switch (metodo.toUpperCase()) {
      case 'PATCH':
        return '$legible (modificar)';
      case 'DELETE':
        return '$legible (borrar)';
      default:
        return legible;
    }
  }
}

enum _Tipo { lectura, escritura, directo }
