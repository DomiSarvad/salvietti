import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/informe_gerente/models/informe_modelos.dart';
import 'package:salvietti_control/features/informe_gerente/repositories/informe_repository.dart';
import 'package:salvietti_control/features/informe_gerente/services/informe_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements InformeRepository {
  List<ResumenProduccion> lista;
  final consultasMerma = <Map<String, dynamic>>[];

  _Repo([List<ResumenProduccion>? lista]) : lista = lista ?? [];

  @override
  Future<List<ResumenProduccion>> resumen({int limite = 200}) async => lista;

  @override
  Future<List<DetalleMermaArea>> mermaDe({required DateTime fecha, required int saborId}) async {
    consultasMerma.add({'fecha': fecha, 'sabor': saborId});
    return const [
      DetalleMermaArea(area: 'soplado', totalMerma: 200, porcentaje: 5.9, alerta: true),
    ];
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) =>
    rol == 'gerente' ? {'informe_produccion:ver'} : {};

Future<InformeService> _svc(String rol, [_Repo? repo]) async {
  final s = InformeService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  test('sin permiso no carga nada', () async {
    final s = await _svc('jefe_produccion');
    expect(s.puedeVer, isFalse);
    expect(s.resumen, isEmpty);
  });

  test('Gerente ve el resumen', () async {
    final repo = _Repo([
      ResumenProduccion(
          fecha: DateTime(2026, 9, 22), saborId: 1, sabor: 'Papaya',
          cajasEsperadas: 24, cajasProducidas: 20, desviacionCajas: -4, desviacionPorcentaje: -16.7),
    ]);
    final s = await _svc('gerente', repo);
    expect(s.puedeVer, isTrue);
    expect(s.resumen.single.alertaDesviacion, isTrue);
  });

  test('sin saborId no consulta la merma', () async {
    final s = await _svc('gerente');
    final fila = ResumenProduccion(fecha: DateTime(2026, 9, 22), sabor: 'Papaya');
    expect(await s.mermaDe(fila), isEmpty);
  });

  test('con saborId consulta la merma de esa fecha y sabor', () async {
    final repo = _Repo();
    final s = await _svc('gerente', repo);
    final fila = ResumenProduccion(fecha: DateTime(2026, 9, 22), saborId: 1, sabor: 'Papaya');
    final detalle = await s.mermaDe(fila);
    expect(detalle.single.area, 'soplado');
    expect(repo.consultasMerma.single, {'fecha': DateTime(2026, 9, 22), 'sabor': 1});
  });

  test('del más reciente al más antiguo, agrupado por día, con filtros y totales', () async {
    final repo = _Repo([
      ResumenProduccion(
          fecha: DateTime(2026, 9, 27), sabor: 'Papaya',
          cajasEsperadas: 18, cajasProducidas: 18, desviacionPorcentaje: 0),
      ResumenProduccion(
          fecha: DateTime(2026, 9, 29), sabor: 'Ross',
          cajasEsperadas: 10, cajasProducidas: 5, desviacionPorcentaje: -50),
      ResumenProduccion(
          fecha: DateTime(2026, 9, 29), sabor: 'Papaya',
          cajasEsperadas: 24, cajasProducidas: 24, desviacionPorcentaje: 0),
    ]);
    final s = await _svc('gerente', repo);
    expect(s.resumen.map((r) => '${r.fecha.day} ${r.sabor}'), ['29 Papaya', '29 Ross', '27 Papaya']);
    expect(s.porDia.length, 2);
    expect(s.totales.esperadas, 52);
    expect(s.totales.conDesvio, 1);
    s.alternarSoloDesvio();
    expect(s.filtrados.single.sabor, 'Ross');
    s.alternarSoloDesvio();
    s.filtrar(s.filtro.conTexto('papaya'));
    expect(s.filtrados.length, 2);
  });
}
