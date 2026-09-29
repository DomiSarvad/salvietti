import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/dashboard/models/dashboard_modelos.dart';
import 'package:salvietti_control/features/dashboard/repositories/dashboard_repository.dart';
import 'package:salvietti_control/features/dashboard/services/dashboard_service.dart';
import 'package:salvietti_control/features/inventario/models/almacen.dart';
import 'package:salvietti_control/features/inventario/models/existencia_item.dart';
import 'package:salvietti_control/features/mermas/models/mermas_modelos.dart';
import 'package:salvietti_control/models/usuario.dart';

class _SuscripcionFalsa implements Suscripcion {
  @override
  void cancelar() {}
}

class _Repo implements DashboardRepository {
  List<ExistenciaItem> existenciasFijas;
  List<MovimientoReciente> movimientosFijos;
  List<EventoMerma> mermasFijas;
  bool fallar = false;
  final consultas = <List<String>>[];

  _Repo({List<ExistenciaItem>? existencias, List<MovimientoReciente>? movimientos, List<EventoMerma>? mermas})
      : existenciasFijas = existencias ?? [],
        movimientosFijos = movimientos ?? [],
        mermasFijas = mermas ?? [];

  @override
  Future<List<Almacen>> almacenes() async => const [
        Almacen(id: 'general', nombre: 'Almacén General'),
        Almacen(id: 'jarabes', nombre: 'Almacén de Jarabes'),
        Almacen(id: 'soplado', nombre: 'Almacén de Soplado'),
        Almacen(id: 'soda_caustica', nombre: 'Almacén de Soda Cáustica'),
      ];

  @override
  Future<List<ExistenciaItem>> existenciasDe(List<String> almacenIds) async {
    if (fallar) throw Exception('sin conexión');
    consultas.add(almacenIds);
    return existenciasFijas.where((e) => almacenIds.contains(e.almacenId)).toList();
  }

  @override
  Future<List<MovimientoReciente>> movimientosRecientes(List<String> almacenIds,
      {int limite = 12}) async {
    if (fallar) throw Exception('sin conexión');
    return movimientosFijos.where((m) => almacenIds.contains(m.almacenId)).toList();
  }

  @override
  Future<List<EventoMerma>> mermasRecientes({int limite = 30}) async {
    if (fallar) throw Exception('sin conexión');
    return mermasFijas;
  }

  @override
  Suscripcion escucharStock(void Function() onCambio) => _SuscripcionFalsa();

  @override
  Suscripcion escucharMermas(void Function() onCambio) => _SuscripcionFalsa();
}

Usuario _usuario(Set<String>? permisos) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: 'almacen', permisos: permisos);

ExistenciaItem _item({
  required int id,
  required String almacenId,
  double cantidad = 10,
  double? dias,
}) =>
    ExistenciaItem(
      itemId: id, codigo: 'IN-000$id', detalle: 'Ítem $id', unidad: 'PZA', categoriaId: 1,
      almacenId: almacenId, cantidadSistema: cantidad, diasExistencia: dias,
    );

Future<DashboardService> _svc(Set<String>? permisos, [_Repo? repo]) async {
  final s = DashboardService(repo ?? _Repo(), _usuario(permisos));
  await s.iniciar();
  return s;
}

void main() {
  test('sin permisos no muestra ningún almacén (denegar por defecto)', () async {
    final s = await _svc(null);
    expect(s.almacenesVisibles, isEmpty);
    expect(s.existencias, isEmpty);
  });

  test('solo consulta los almacenes que el rol puede ver', () async {
    final repo = _Repo();
    final s = await _svc({'inventario_general:ver', 'inventario_jarabes:ver'}, repo);
    expect(s.almacenesVisibles.map((a) => a.id), ['general', 'jarabes']);
    expect(repo.consultas.single, ['general', 'jarabes']);
  });

  test('el resumen por almacén separa críticos, bajos y óptimos', () async {
    final repo = _Repo(existencias: [
      _item(id: 1, almacenId: 'general', dias: 2), // crítico
      _item(id: 2, almacenId: 'general', dias: 5), // bajo
      _item(id: 3, almacenId: 'general', dias: 30), // óptimo
      _item(id: 4, almacenId: 'general', dias: null), // sin datos
    ]);
    final s = await _svc({'inventario_general:ver'}, repo);
    final r = s.resumenes.single;
    expect(r.almacen.id, 'general');
    expect(r.total, 4);
    expect(r.criticos, 1);
    expect(r.bajos, 1);
    expect(r.optimos, 1);
  });

  test('en riesgo ordena de menor a mayor y deja afuera los sin dato', () async {
    final repo = _Repo(existencias: [
      _item(id: 1, almacenId: 'general', dias: 5),
      _item(id: 2, almacenId: 'general', dias: 1),
      _item(id: 3, almacenId: 'general', dias: null),
      _item(id: 4, almacenId: 'general', dias: 20), // no entra: no está en riesgo
    ]);
    final s = await _svc({'inventario_general:ver'}, repo);
    expect(s.enRiesgo.map((e) => e.itemId), [2, 1]);
  });

  test('menor stock ordena por cantidad y se queda con los primeros 6', () async {
    final repo = _Repo(existencias: [
      for (var i = 1; i <= 8; i++) _item(id: i, almacenId: 'general', cantidad: (9 - i).toDouble()),
    ]);
    final s = await _svc({'inventario_general:ver'}, repo);
    expect(s.menorStock.length, 6);
    expect(s.menorStock.first.itemId, 8); // cantidad 1, la más baja
  });

  test('sin conexión avisa y no rompe', () async {
    final repo = _Repo()..fallar = true;
    final s = await _svc({'inventario_general:ver'}, repo);
    expect(s.error, isNotNull);
    expect(s.existencias, isEmpty);
  });
}
