import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/soda_caustica/models/soda_modelos.dart';
import 'package:salvietti_control/features/soda_caustica/repositories/soda_repository.dart';
import 'package:salvietti_control/features/soda_caustica/services/soda_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements SodaRepository {
  List<EntregaSoda> lista;
  ErrorNegocioSoda? negocio;
  final registradas = <Map<String, dynamic>>[];

  _Repo([List<EntregaSoda>? lista]) : lista = lista ?? [];

  @override
  Future<List<ItemInventario>> items({String? busqueda}) async =>
      const [ItemInventario(id: 1, codigo: 'IN-0050', detalle: 'Soda cáustica', unidad: 'KG')];

  @override
  Future<List<EntregaSoda>> entregas({int limite = 200}) async => lista;

  @override
  Future<int> registrarEntrega({
    required int itemId,
    required double cantidad,
    required String entregadoA,
    String? areaRecibe,
    String? motivo,
  }) async {
    if (negocio != null) throw negocio!;
    registradas.add({
      'item': itemId, 'cantidad': cantidad, 'entregadoA': entregadoA,
      'area': areaRecibe, 'motivo': motivo,
    });
    return 3;
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'soda_caustica':
      return {'soda_caustica:ver', 'soda_caustica:crear'};
    case 'gerente':
      return {'soda_caustica:ver'};
    default:
      return {};
  }
}

const _item = ItemInventario(id: 1, codigo: 'IN-0050', detalle: 'Soda cáustica', unidad: 'KG');

Future<SodaService> _svc(String rol, [_Repo? repo]) async {
  final s = SodaService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('almacen');
      expect(s.puedeVer, isFalse);
      expect(s.entregas, isEmpty);
    });

    test('Gerente ve pero no puede registrar', () async {
      final s = await _svc('gerente');
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(await s.registrarEntrega(item: _item, cantidad: 1, entregadoA: 'Juan Pérez'),
          contains('permiso'));
    });
  });

  group('registrar entrega', () {
    test('exige ítem, cantidad y a quién se entrega', () async {
      final s = await _svc('soda_caustica');
      expect(await s.registrarEntrega(item: null, cantidad: 1, entregadoA: 'Juan'),
          contains('ítem'));
      expect(await s.registrarEntrega(item: _item, cantidad: null, entregadoA: 'Juan'),
          contains('cantidad'));
      expect(await s.registrarEntrega(item: _item, cantidad: 1, entregadoA: 'J'),
          contains('a quién'));
    });

    test('registra y traduce el error del servidor (sin stock)', () async {
      final repo = _Repo();
      final s = await _svc('soda_caustica', repo);
      expect(
          await s.registrarEntrega(
              item: _item, cantidad: 5, entregadoA: 'Juan Pérez',
              areaRecibe: 'Mantenimiento', motivo: 'Limpieza de tanques'),
          isNull);
      expect(repo.registradas.single,
          {'item': 1, 'cantidad': 5.0, 'entregadoA': 'Juan Pérez', 'area': 'Mantenimiento', 'motivo': 'Limpieza de tanques'});

      repo.negocio = const ErrorNegocioSoda('No hay suficiente stock: hay 2, se quieren entregar 5.');
      expect(await s.registrarEntrega(item: _item, cantidad: 5, entregadoA: 'Juan Pérez'),
          'No hay suficiente stock: hay 2, se quieren entregar 5.');
    });
  });
}
