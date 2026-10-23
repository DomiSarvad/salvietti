import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/compras/models/compras_modelos.dart';
import 'package:salvietti_control/features/compras/repositories/compras_repository.dart';
import 'package:salvietti_control/features/compras/services/compras_service.dart';
import 'package:salvietti_control/models/usuario.dart';

const _tapa = ItemCompra(id: 1, codigo: 'IN-1', detalle: 'Tapa negra', unidad: 'PZA');
const _azucar = ItemCompra(id: 2, codigo: 'MP-1', detalle: 'Azúcar', unidad: 'KG');

PedidoCompra _pedido(int id, EstadoCompra e, {String solicitante = 'alm'}) => PedidoCompra(
      id: id,
      fecha: DateTime(2026, 10, 23),
      motivo: null,
      estado: e,
      solicitanteId: solicitante,
      solicitanteNombre: 'Almacén',
      resueltoPorNombre: null,
      resueltoEn: null,
      respuesta: null,
      lineas: const [],
    );

class _Repo implements ComprasRepository {
  List<PedidoCompra> lista = [];
  final creados = <List<LineaNueva>>[];
  final resueltos = <Map<String, Object?>>[];
  ErrorNegocioCompra? negocio;

  @override
  Future<List<PedidoCompra>> pedidos({int limite = 200}) async => lista;
  @override
  Future<List<ItemCompra>> items() async => const [_tapa, _azucar];
  @override
  Future<int> crear(String? motivo, List<LineaNueva> lineas) async {
    if (negocio != null) throw negocio!;
    creados.add(lineas);
    return 9;
  }

  @override
  Future<void> resolver(int id, {required bool aprobar, String? respuesta}) async =>
      resueltos.add({'id': id, 'aprobar': aprobar, 'respuesta': respuesta});
  @override
  Future<void> anular(int id) async => resueltos.add({'id': id, 'anulado': true});
  @override
  Suscripcion escucharCambios(void Function() onCambio) => const SuscripcionNula();
}

Usuario _almacen() =>
    Usuario(id: 'alm', nombreCompleto: 'Almacén', rol: 'almacen', permisos: {'compras:ver', 'compras:crear'});
Usuario _gerente() =>
    Usuario(id: 'ger', nombreCompleto: 'Gerente', rol: 'gerente', permisos: {'compras:ver', 'compras:aprobar'});

Future<ComprasService> _svc(Usuario u, [_Repo? repo]) async {
  final s = ComprasService(repo ?? _Repo(), u);
  await s.iniciar();
  return s;
}

void main() {
  test('Almacén crea un pedido con varios ítems', () async {
    final repo = _Repo();
    final s = await _svc(_almacen(), repo);
    expect(
        await s.crear('stock bajo', const [
          LineaNueva(item: _tapa, cantidad: 5000),
          LineaNueva(item: _azucar, cantidad: 46, nota: '  1 quintal  '),
        ]),
        isNull);
    expect(repo.creados.single, hasLength(2));
    expect(repo.creados.single[1].nota, '1 quintal');
  });

  test('valida: sin ítems, cantidad cero, ítem repetido y sin permiso', () async {
    final s = await _svc(_almacen());
    expect(await s.crear(null, const []), contains('al menos un ítem'));
    expect(await s.crear(null, const [LineaNueva(item: _tapa, cantidad: 0)]), contains('mayor a cero'));
    expect(
        await s.crear(null, const [LineaNueva(item: _tapa, cantidad: 1), LineaNueva(item: _tapa, cantidad: 2)]),
        contains('dos veces'));
    final g = await _svc(_gerente());
    expect(await g.crear(null, const [LineaNueva(item: _tapa, cantidad: 1)]), contains('permiso'));
  });

  test('el Gerente aprueba; para rechazar tiene que explicar el motivo', () async {
    final repo = _Repo()..lista = [_pedido(1, EstadoCompra.pendiente)];
    final g = await _svc(_gerente(), repo);
    expect(g.filtro, EstadoCompra.pendiente); // entra directo a lo que tiene que resolver
    expect(await g.rechazar(repo.lista.first, '  '), contains('motivo'));
    expect(await g.aprobar(repo.lista.first, respuesta: ' Ok '), isNull);
    expect(repo.resueltos.single, {'id': 1, 'aprobar': true, 'respuesta': 'Ok'});
  });

  test('Almacén no puede aprobar; y solo anula lo suyo y pendiente', () async {
    final repo = _Repo()
      ..lista = [
        _pedido(1, EstadoCompra.pendiente),
        _pedido(2, EstadoCompra.aprobado),
        _pedido(3, EstadoCompra.pendiente, solicitante: 'otro'),
      ];
    final s = await _svc(_almacen(), repo);
    expect(await s.aprobar(repo.lista.first), contains('permiso'));
    expect(s.puedeAnular(repo.lista[0]), isTrue);
    expect(s.puedeAnular(repo.lista[1]), isFalse);
    expect(s.puedeAnular(repo.lista[2]), isFalse);
    expect(await s.anular(repo.lista[0]), isNull);
  });

  test('muestra el error del servidor tal cual', () async {
    final repo = _Repo()..negocio = const ErrorNegocioCompra('Uno de los ítems no existe o está dado de baja.');
    final s = await _svc(_almacen(), repo);
    expect(await s.crear(null, const [LineaNueva(item: _tapa, cantidad: 1)]), contains('dado de baja'));
  });
}
