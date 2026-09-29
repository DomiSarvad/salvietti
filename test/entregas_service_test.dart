import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/entregas/models/entregas_modelos.dart';
import 'package:salvietti_control/features/entregas/repositories/entregas_repository.dart';
import 'package:salvietti_control/features/entregas/services/entregas_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements EntregasRepository {
  List<Pedido> lista;
  bool fallar = false;
  ErrorNegocio? negocio;

  final entregados = <int>[];
  final confirmados = <int>[];
  final resueltos = <int>[];
  final anulados = <int>[];
  Map<String, dynamic>? ultimoPedido;

  _Repo([List<Pedido>? lista]) : lista = lista ?? [];

  @override
  Future<List<Pedido>> pedidos({int limite = 200}) async {
    if (fallar) throw Exception('sin conexión');
    return lista;
  }

  @override
  Future<List<ItemPedible>> itemsPedibles(String almacenOrigen) async => const [
        ItemPedible(id: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG', disponible: 100),
        ItemPedible(id: 2, codigo: 'IN-0002', detalle: 'Cápsula negra', unidad: 'PZA', disponible: 5),
      ];

  @override
  Future<int> crearPedido({
    String? area,
    String? motivo,
    required List<LineaNueva> lineas,
    bool entregar = false,
  }) async {
    if (negocio != null) throw negocio!;
    ultimoPedido = {'area': area, 'motivo': motivo, 'lineas': lineas, 'entregar': entregar};
    return 99;
  }

  @override
  Future<void> entregar(int pedidoId, {Map<int, double>? cantidades}) async {
    if (negocio != null) throw negocio!;
    entregados.add(pedidoId);
  }

  @override
  Future<void> confirmar(int pedidoId, List<ConfirmacionLinea> lineas, {String? nota}) async {
    if (negocio != null) throw negocio!;
    confirmados.add(pedidoId);
  }

  @override
  Future<void> resolver(int pedidoId, String resolucion) async {
    if (negocio != null) throw negocio!;
    resueltos.add(pedidoId);
  }

  @override
  Future<void> anular(int pedidoId, String motivo) async {
    if (negocio != null) throw negocio!;
    anulados.add(pedidoId);
  }

  final devoluciones = <Map<String, dynamic>>[];

  @override
  Future<void> registrarDevolucion(int lineaId, double cantidad, {String? motivo}) async {
    if (negocio != null) throw negocio!;
    devoluciones.add({'linea': lineaId, 'cantidad': cantidad, 'motivo': motivo});
  }
}

Usuario _usuario(String rol) => Usuario(
    id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'almacen':
      return {
        'entregas:ver', 'entregas:crear', 'entregas:editar', 'solicitudes:crear',
      };
    case 'jarabes':
      return {'entregas:ver', 'entregas:editar', 'solicitudes:crear'};
    case 'llenadora':
      return {'entregas:ver', 'entregas:editar', 'solicitudes:crear'};
    case 'gerente':
      return {'entregas:ver'};
    default:
      return {};
  }
}

LineaPedido _linea({
  int id = 1,
  double pedida = 5,
  double? entregada,
  double? recibida,
  bool? ok,
  String? obs,
  double devuelta = 0,
}) =>
    LineaPedido(
      id: id, itemId: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG',
      cantidadPedida: pedida, cantidadEntregada: entregada, cantidadRecibida: recibida,
      recibidoOk: ok, observacion: obs, cantidadDevuelta: devuelta,
    );

Pedido _pedido({
  int id = 1,
  EstadoPedido estado = EstadoPedido.pendiente,
  String solicitante = 'otro',
  String area = 'jarabes',
  List<LineaPedido>? lineas,
}) =>
    Pedido(
      id: id, fecha: DateTime(2026, 9, 21), areaDestino: area, almacenOrigen: 'general',
      estado: estado, solicitanteId: solicitante, lineas: lineas ?? [_linea()],
    );

Future<EntregasService> _svc(String rol, [_Repo? repo]) async {
  final s = EntregasService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver Entregas no carga nada', () async {
      final s = await _svc('control_calidad');
      expect(s.puedeVer, isFalse);
      expect(s.pedidos, isEmpty);
    });

    test('Almacén puede pedir para cualquier área y entregar', () async {
      final s = await _svc('almacen');
      expect(s.esAlmacen, isTrue);
      expect(s.puedeCrearPedido, isTrue);
      expect(s.puedeEntregar(_pedido()), isTrue);
    });

    test('Jarabes solo pide para su propia área y no entrega', () async {
      final s = await _svc('jarabes');
      expect(s.areaPropia, 'jarabes');
      expect(s.esAlmacen, isFalse);
      expect(s.puedeEntregar(_pedido()), isFalse);
    });

    test('confirma solo el área destino o quien pidió, y solo si ya se entregó', () async {
      final s = await _svc('jarabes');
      final entregado = _pedido(estado: EstadoPedido.entregado, area: 'jarabes');
      expect(s.puedeConfirmar(entregado), isTrue);
      expect(s.puedeConfirmar(_pedido(estado: EstadoPedido.entregado, area: 'soplado')), isFalse);
      expect(s.puedeConfirmar(_pedido(estado: EstadoPedido.pendiente, area: 'jarabes')), isFalse);
    });

    test('el solicitante puede confirmar aunque sea de otra área', () async {
      final s = await _svc('jarabes');
      final p = _pedido(
          estado: EstadoPedido.entregado, area: 'soplado', solicitante: 'u1');
      expect(s.puedeConfirmar(p), isTrue);
    });

    test('solo Almacén resuelve observaciones; anula quien pidió o Almacén', () async {
      final almacen = await _svc('almacen');
      final jarabes = await _svc('jarabes');
      final observado = _pedido(estado: EstadoPedido.observado);
      expect(almacen.puedeResolver(observado), isTrue);
      expect(jarabes.puedeResolver(observado), isFalse);

      final propio = _pedido(solicitante: 'u1');
      expect(jarabes.puedeAnular(propio), isTrue);
      expect(jarabes.puedeAnular(_pedido(solicitante: 'otro')), isFalse);
      expect(almacen.puedeAnular(_pedido(solicitante: 'otro')), isTrue);
    });
  });

  group('crear pedido', () {
    test('exige al menos un ítem y rechaza repetidos o cantidades inválidas', () async {
      final s = await _svc('jarabes');
      expect(await s.crearPedido(lineas: []), contains('un ítem'));
      expect(
          await s.crearPedido(lineas: [
            const LineaNueva(itemId: 1, cantidad: 1),
            const LineaNueva(itemId: 1, cantidad: 2),
          ]),
          contains('repetido'));
      expect(
          await s.crearPedido(lineas: [const LineaNueva(itemId: 1, cantidad: 0)]),
          contains('mayor a cero'));
    });

    test('quien no puede pedir, no crea nada', () async {
      final repo = _Repo();
      final s = await _svc('control_calidad', repo);
      expect(
          await s.crearPedido(lineas: [const LineaNueva(itemId: 1, cantidad: 1)]),
          contains('permiso'));
      expect(repo.ultimoPedido, isNull);
    });

    test('un área normal pide para sí misma, sin elegir destino', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      final error = await s.crearPedido(lineas: [const LineaNueva(itemId: 1, cantidad: 3)]);
      expect(error, isNull);
      expect(repo.ultimoPedido!['area'], isNull); // el servidor la deduce del rol
    });

    test('solo Almacén puede entregar al crear, y valida el stock disponible', () async {
      final repo = _Repo();
      final jarabes = await _svc('jarabes', repo);
      expect(
          await jarabes.crearPedido(
              area: 'jarabes', lineas: [const LineaNueva(itemId: 1, cantidad: 1)],
              entregarAhora: true),
          contains('Solo Almacén'));

      final almacen = await _svc('almacen', repo);
      expect(
          await almacen.crearPedido(
              area: 'jarabes', lineas: [const LineaNueva(itemId: 2, cantidad: 999)],
              entregarAhora: true),
          contains('No alcanza'));
      expect(
          await almacen.crearPedido(
              area: 'jarabes', lineas: [const LineaNueva(itemId: 1, cantidad: 10)],
              entregarAhora: true),
          isNull);
      expect(repo.ultimoPedido!['entregar'], isTrue);
    });

    test('sin conexión, no crea nada y avisa', () async {
      // Simula error de red en la escritura (no en la carga inicial).
      final repoFalla = _RepoQueFallaAlEscribir();
      final s2 = EntregasService(repoFalla, _usuario('jarabes'));
      await s2.iniciar();
      expect(
          await s2.crearPedido(lineas: [const LineaNueva(itemId: 1, cantidad: 1)]),
          contains('Sin conexión'));
    });
  });

  group('entregar', () {
    test('no deja entregar más de lo pedido ni en negativo', () async {
      final repo = _Repo();
      final s = await _svc('almacen', repo);
      final p = _pedido(lineas: [_linea(id: 7, pedida: 5)]);
      expect(await s.entregar(p, cantidades: {7: 10}), contains('más de lo pedido'));
      expect(await s.entregar(p, cantidades: {7: -1}), contains('negativas'));
      expect(await s.entregar(p, cantidades: {7: 0}), contains('anulá el pedido'));
      expect(repo.entregados, isEmpty);
    });

    test('entrega parcial válida y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('almacen', repo);
      final p = _pedido(lineas: [_linea(id: 7, pedida: 5)]);
      expect(await s.entregar(p, cantidades: {7: 3}), isNull);
      expect(repo.entregados, [1]);

      repo.negocio = const ErrorNegocio('Stock insuficiente de "Azúcar": hay 2, se piden 3.');
      expect(await s.entregar(p), contains('Stock insuficiente'));
    });
  });

  group('confirmar', () {
    test('exige observación cuando algo no está conforme o difiere la cantidad', () async {
      final s = await _svc('jarabes');
      final l = _linea(id: 3, entregada: 5);
      final p = _pedido(estado: EstadoPedido.entregado, lineas: [l]);

      expect(
          await s.confirmar(p, [
            const ConfirmacionLinea(lineaId: 3, recibidoOk: false, cantidadRecibida: 5),
          ]),
          contains('observación'));
      expect(
          await s.confirmar(p, [
            const ConfirmacionLinea(lineaId: 3, recibidoOk: true, cantidadRecibida: 4),
          ]),
          contains('observación'));
      expect(
          await s.confirmar(p, [
            const ConfirmacionLinea(
                lineaId: 3, recibidoOk: false, cantidadRecibida: 4, observacion: 'Faltó 1kg'),
          ]),
          isNull);
    });

    test('no deja recibir más de lo entregado', () async {
      final s = await _svc('jarabes');
      final p = _pedido(
          estado: EstadoPedido.entregado, lineas: [_linea(id: 3, entregada: 5)]);
      expect(
          await s.confirmar(p, [
            const ConfirmacionLinea(lineaId: 3, recibidoOk: true, cantidadRecibida: 6),
          ]),
          contains('más de lo entregado'));
    });

    test('exige revisar todas las líneas del pedido', () async {
      final s = await _svc('jarabes');
      final p = _pedido(
          estado: EstadoPedido.entregado,
          lineas: [_linea(id: 3, entregada: 5), _linea(id: 4, entregada: 2)]);
      expect(
          await s.confirmar(p, [
            const ConfirmacionLinea(lineaId: 3, recibidoOk: true, cantidadRecibida: 5),
          ]),
          contains('Falta revisar'));
    });
  });

  group('resolver y anular', () {
    test('el texto no puede ser demasiado corto ni demasiado largo', () async {
      final s = await _svc('almacen');
      final p = _pedido(estado: EstadoPedido.observado);
      expect(await s.resolver(p, 'ok'), contains('3 a 300'));
      expect(await s.resolver(p, 'x' * 301), contains('3 a 300'));
      expect(await s.resolver(p, 'Se repuso el faltante'), isNull);
    });

    test('anula un pedido propio pendiente', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      final propio = _pedido(solicitante: 'u1');
      expect(await s.anular(propio, 'Ya no hace falta'), isNull);
      expect(repo.anulados, [1]);
    });
  });

  group('bandejas', () {
    test('agrupa por estado y cuenta lo pendiente de mi acción', () async {
      final repo = _Repo([
        _pedido(id: 1, estado: EstadoPedido.pendiente, area: 'jarabes'),
        _pedido(id: 2, estado: EstadoPedido.entregado, area: 'jarabes'),
        _pedido(id: 3, estado: EstadoPedido.cerrado, area: 'soplado'),
        _pedido(id: 4, estado: EstadoPedido.anulado, area: 'soplado'),
      ]);
      final s = await _svc('jarabes', repo);
      expect(s.cantidadEn(BandejaPedidos.pendientes), 1);
      expect(s.cantidadEn(BandejaPedidos.cerrados), 2); // cerrado + anulado
      s.elegirBandeja(BandejaPedidos.porConfirmar);
      expect(s.visibles.map((p) => p.id), [2]);
      expect(s.pendientesDeMiAccion, 1); // solo puede confirmar el #2 (su área)
    });
  });

  group('devolución', () {
    test('solo Almacén, y solo si el pedido ya se entregó', () async {
      final jarabes = await _svc('jarabes');
      final l = _linea(entregada: 5);
      expect(jarabes.puedeDevolver(_pedido(lineas: [l]), l), isFalse);

      final almacen = await _svc('almacen');
      final pendiente = _linea(entregada: null);
      expect(almacen.puedeDevolver(_pedido(estado: EstadoPedido.pendiente, lineas: [pendiente]), pendiente),
          isFalse);

      final entregada = _linea(entregada: 5);
      expect(
          almacen.puedeDevolver(_pedido(estado: EstadoPedido.cerrado, lineas: [entregada]), entregada),
          isTrue);
    });

    test('no deja devolver más de lo disponible (entregado menos ya devuelto)', () async {
      final almacen = await _svc('almacen');
      final l = _linea(entregada: 5, devuelta: 2);
      final p = _pedido(estado: EstadoPedido.cerrado, lineas: [l]);
      expect(await almacen.registrarDevolucion(p, l, 4, null), contains('quedan'));
      expect(await almacen.registrarDevolucion(p, l, 0, null), contains('mayor a cero'));
    });

    test('registra la devolución', () async {
      final repo = _Repo();
      final almacen = await _svc('almacen', repo);
      final l = _linea(id: 9, entregada: 5, devuelta: 2);
      final p = _pedido(estado: EstadoPedido.cerrado, lineas: [l]);
      expect(await almacen.registrarDevolucion(p, l, 3, 'Sobró del pedido'), isNull);
      expect(repo.devoluciones.single, {'linea': 9, 'cantidad': 3.0, 'motivo': 'Sobró del pedido'});
    });
  });
}

/// Repositorio que carga bien pero falla al escribir (simula sin conexión).
class _RepoQueFallaAlEscribir extends _Repo {
  @override
  Future<int> crearPedido({
    String? area,
    String? motivo,
    required List<LineaNueva> lineas,
    bool entregar = false,
  }) async =>
      Future.error(Exception('Connection timeout / socket'));
}
