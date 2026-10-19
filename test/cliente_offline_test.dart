import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:salvietti_control/core/constants.dart';
import 'package:salvietti_control/services/cliente_offline.dart';
import 'package:salvietti_control/services/cola_offline.dart';

const _base = 'https://demo.supabase.co';

/// JWT de mentira: solo importa el `sub` (ClienteOffline no valida la firma).
String _token(String sub) {
  String parte(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${parte({'alg': 'HS256'})}.${parte({'sub': sub})}.firma';
}

http.Request _pedido(String metodo, String ruta, {Object? cuerpo, String usuario = 'u1'}) {
  final r = http.Request(metodo, Uri.parse('$_base$ruta'))
    ..headers['Authorization'] = 'Bearer ${_token(usuario)}'
    ..headers['apikey'] = 'anon';
  if (cuerpo != null) {
    r.headers['Content-Type'] = 'application/json';
    r.body = jsonEncode(cuerpo);
  }
  return r;
}

Future<http.Response> _enviar(http.Client c, http.Request r) async =>
    http.Response.fromStream(await c.send(r));

/// Simula "no hay internet": falla como falla el cliente real sin red.
final _sinRed = MockClient((_) async => throw http.ClientException('Failed host lookup'));

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('offline_test').path);
    await ColaOffline.init();
  });

  setUp(() async {
    for (final b in [
      HiveBoxes.cacheLecturas,
      HiveBoxes.colaOffline,
      HiveBoxes.erroresOffline,
      HiveBoxes.idsTemporales,
    ]) {
      await Hive.box(b).clear();
    }
    ClienteOffline.sinInterfaz = false;
    ClienteOffline.hayRed.value = true;
  });

  test('una lectura sin internet devuelve la última copia guardada', () async {
    final enLinea = ClienteOffline(MockClient((_) async => http.Response('[{"id":1}]', 200)));
    await _enviar(enLinea, _pedido('GET', '/rest/v1/sabores?select=id'));

    final r = await _enviar(ClienteOffline(_sinRed), _pedido('GET', '/rest/v1/sabores?select=id'));
    expect(r.statusCode, 200);
    expect(r.body, '[{"id":1}]');
    expect(ClienteOffline.hayRed.value, isFalse);
  });

  test('la copia es por usuario: otro usuario sin copia recibe el error', () async {
    final enLinea = ClienteOffline(MockClient((_) async => http.Response('[]', 200)));
    await _enviar(enLinea, _pedido('GET', '/rest/v1/sabores', usuario: 'u1'));

    expect(
      () => _enviar(ClienteOffline(_sinRed), _pedido('GET', '/rest/v1/sabores', usuario: 'u2')),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('una escritura sin internet se encola y devuelve un id provisorio', () async {
    final r = await _enviar(ClienteOffline(_sinRed),
        _pedido('POST', '/rest/v1/rpc/soplado_iniciar_corrida', cuerpo: {'p_sabor_id': 3}));

    expect(r.statusCode, 200);
    final id = jsonDecode(r.body) as int;
    expect(id, lessThan(0));
    expect(ColaOffline.cantidadPendientes, 1);
    expect(ColaOffline.pendientes().single.descripcion, 'Soplado: iniciar corrida');
    // Sin el token guardado en disco.
    expect(ColaOffline.pendientes().single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
  });

  test('al subir, el id provisorio se reemplaza por el real en lo que sigue', () async {
    final offline = ClienteOffline(_sinRed);
    final r1 = await _enviar(offline,
        _pedido('POST', '/rest/v1/rpc/soplado_iniciar_corrida', cuerpo: {'p_sabor_id': 3}));
    final temporal = jsonDecode(r1.body) as int;
    await _enviar(offline, _pedido('POST', '/rest/v1/rpc/soplado_finalizar_corrida',
        cuerpo: {'p_id': temporal, 'p_botellas_sopladas': 100}));
    expect(ColaOffline.cantidadPendientes, 2);

    final recibidos = <Map>[];
    final servidor = MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer nuevo');
      recibidos.add({'ruta': req.url.path, 'cuerpo': jsonDecode(req.body)});
      return http.Response(req.url.path.endsWith('iniciar_corrida') ? '57' : '', 200);
    });
    final res = await ClienteOffline.subirCola(
        usuario: 'u1', token: () => 'nuevo', refrescarToken: () async {}, clienteHttp: servidor);

    expect(res.subidas, 2);
    expect(res.rechazadas, 0);
    expect(recibidos[1]['cuerpo']['p_id'], 57);
    expect(ColaOffline.cantidadPendientes, 0);
  });

  test('un rechazo del servidor no traba el resto; lo que dependía de él también queda con error',
      () async {
    final offline = ClienteOffline(_sinRed);
    final r1 = await _enviar(offline,
        _pedido('POST', '/rest/v1/rpc/jarabes_iniciar_preparado', cuerpo: {'p_cantidad': 9}));
    final temporal = jsonDecode(r1.body) as int;
    await _enviar(offline,
        _pedido('POST', '/rest/v1/rpc/jarabes_finalizar_preparado', cuerpo: {'p_id': temporal}));
    await _enviar(offline, _pedido('POST', '/rest/v1/rpc/mermas_registrar', cuerpo: {'p_x': 1}));

    final servidor = MockClient((req) async => req.url.path.endsWith('iniciar_preparado')
        ? http.Response('{"message":"Stock insuficiente","code":"P0001"}', 400)
        : http.Response('8', 200));
    final res = await ClienteOffline.subirCola(
        usuario: 'u1', token: () => 't', refrescarToken: () async {}, clienteHttp: servidor);

    expect(res.subidas, 1); // la merma
    expect(res.rechazadas, 2);
    final errores = ColaOffline.conError();
    expect(errores.first.error, 'Stock insuficiente');
    expect(errores[1].error, contains('Depende de otra operación'));
    expect(ColaOffline.cantidadPendientes, 0);
  });

  test('con algo pendiente, una escritura nueva va detrás aunque haya red', () async {
    await _enviar(ClienteOffline(_sinRed),
        _pedido('POST', '/rest/v1/rpc/mermas_registrar', cuerpo: {'p_x': 1}));
    var llamadas = 0;
    final conRed = ClienteOffline(MockClient((_) async {
      llamadas++;
      return http.Response('1', 200);
    }));
    await _enviar(conRed, _pedido('POST', '/rest/v1/rpc/mermas_registrar', cuerpo: {'p_x': 2}));
    expect(llamadas, 0);
    expect(ColaOffline.cantidadPendientes, 2);
  });

  test('si la conexión se corta esperando la respuesta, no se encola (podría duplicarse)',
      () async {
    final cortado =
        ClienteOffline(MockClient((_) async => throw http.ClientException('Connection closed')));
    expect(
      () => _enviar(cortado, _pedido('POST', '/rest/v1/rpc/mermas_registrar', cuerpo: {'p': 1})),
      throwsA(isA<http.ClientException>()),
    );
    expect(ColaOffline.cantidadPendientes, 0);
  });

  test('lo que exige estar en línea no se encola', () async {
    final c = ClienteOffline(_sinRed);
    for (final ruta in ['/rest/v1/rpc/crear_usuario_admin', '/rest/v1/permisos_rol']) {
      await expectLater(
          () => _enviar(c, _pedido('POST', ruta, cuerpo: {})), throwsA(isA<http.ClientException>()));
    }
    expect(ColaOffline.cantidadPendientes, 0);
  });

  test('un insert con .select().single() sin internet devuelve la fila con id provisorio', () async {
    final req = _pedido('POST', '/rest/v1/inv_proveedores', cuerpo: {'nombre': 'ACME'})
      ..headers['Prefer'] = 'return=representation'
      ..headers['Accept'] = 'application/vnd.pgrst.object+json';
    final r = await _enviar(ClienteOffline(_sinRed), req);
    final fila = jsonDecode(r.body) as Map;
    expect(fila['nombre'], 'ACME');
    expect(fila['id'] as int, lessThan(0));
  });

  test('funciona a través del cliente real de Supabase (postgrest)', () async {
    var hayInternet = true;
    final db = SupabaseClient(_base, 'anon',
        httpClient: ClienteOffline(MockClient((req) async {
          if (!hayInternet) throw http.ClientException('Failed host lookup');
          return http.Response('[{"id":1,"nombre":"Fresa"}]', 200,
              headers: {'content-type': 'application/json'});
        })));

    expect(await db.from('sabores').select('id, nombre'), hasLength(1));
    hayInternet = false;
    final copia = await db.from('sabores').select('id, nombre');
    expect(copia.single['nombre'], 'Fresa');

    final id = await db.rpc('soplado_iniciar_corrida', params: {'p_sabor_id': 1});
    expect((id as num).toInt(), lessThan(0));
    await db.rpc('soplado_finalizar_corrida', params: {'p_id': id});
    expect(ColaOffline.cantidadPendientes, 2);
  });
}
