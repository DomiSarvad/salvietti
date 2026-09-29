import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/mermas/models/mermas_modelos.dart';
import 'package:salvietti_control/features/mermas/repositories/mermas_repository.dart';
import 'package:salvietti_control/features/mermas/services/mermas_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements MermasRepository {
  ErrorNegocioMermas? negocio;
  final registrados = <Map<String, dynamic>>[];

  @override
  Future<List<Sabor>> sabores() async =>
      const [Sabor(id: 1, nombre: 'Papaya'), Sabor(id: 2, nombre: 'Ross')];

  @override
  Future<List<Presentacion>> presentaciones() async =>
      const [Presentacion(id: 10, nombre: '2.5 L')];

  @override
  Future<List<EventoMerma>> consolidado() async => [
        EventoMerma(
            origen: 'soplado', id: 1, fecha: DateTime(2026, 9, 22), area: 'soplado',
            sabor: 'Papaya', presentacion: '2.5 L', totalMerma: 200, producido: 3400,
            porcentaje: 5.9, alerta: true),
        EventoMerma(
            origen: 'llenadora', id: 2, fecha: DateTime(2026, 9, 22), area: 'llenadora',
            sabor: 'Papaya', presentacion: '2.5 L', totalMerma: 20, producido: 3400,
            porcentaje: 0.6, alerta: false),
      ];

  @override
  Future<int> registrar({
    required String area,
    required int saborId,
    required List<MapEntry<String, double>> causas,
    int? presentacionId,
    double? cantidadProducida,
    String? motivo,
  }) async {
    if (negocio != null) throw negocio!;
    registrados.add({
      'area': area, 'sabor': saborId, 'causas': causas,
      'producido': cantidadProducida, 'motivo': motivo,
    });
    return 5;
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'jarabes':
      return {'mermas:ver', 'mermas:crear'};
    case 'control_calidad':
      return {'mermas:ver', 'mermas:crear'};
    case 'jefe_produccion':
      return {'mermas:ver', 'mermas:crear'};
    case 'gerente':
      return {'mermas:ver'};
    default:
      return {};
  }
}

Future<MermasService> _svc(String rol, [_Repo? repo]) async {
  final s = MermasService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos y áreas', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('soplado');
      expect(s.puedeVer, isFalse);
      expect(s.consolidado, isEmpty);
    });

    test('Gerente ve el consolidado y el alertado, pero no puede crear', () async {
      final s = await _svc('gerente');
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(s.consolidado.length, 2);
      expect(s.conAlerta.single.origen, 'soplado');
      expect(await s.registrar(area: AreaMerma.jarabes, saborId: 1, causas: {'menor_volumen': 5}),
          contains('permiso'));
    });

    test('Jarabes solo puede cargar su propia área', () async {
      final s = await _svc('jarabes');
      expect(s.areasPermitidas, [AreaMerma.jarabes]);
      expect(
          await s.registrar(area: AreaMerma.calidad, saborId: 1, causas: {'exceso_agua': 5}),
          contains('no registra mermas de esa área'));
    });
  });

  group('registrar', () {
    test('exige área, sabor y al menos una causa', () async {
      final s = await _svc('jarabes');
      expect(await s.registrar(area: null, saborId: 1, causas: {'menor_volumen': 5}),
          contains('área'));
      expect(await s.registrar(area: AreaMerma.jarabes, saborId: null, causas: {'menor_volumen': 5}),
          contains('sabor'));
      expect(await s.registrar(area: AreaMerma.jarabes, saborId: 1, causas: {'menor_volumen': 0}),
          contains('causa'));
    });

    test('registra con las causas mayores a cero, y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      expect(
          await s.registrar(
              area: AreaMerma.jarabes,
              saborId: 1,
              causas: {'menor_volumen': 8, 'diferencia_peso_insumos': 0},
              cantidadProducida: 200,
              motivo: 'Corte de energía'),
          isNull);
      final guardado = repo.registrados.single;
      expect(guardado['area'], 'jarabes');
      expect((guardado['causas'] as List).length, 1);

      repo.negocio = const ErrorNegocioMermas('Causa inválida para el área jarabes: exceso_agua.');
      expect(
          await s.registrar(area: AreaMerma.jarabes, saborId: 1, causas: {'menor_volumen': 5}),
          'Causa inválida para el área jarabes: exceso_agua.');
    });

    test('rechaza producido negativo', () async {
      final s = await _svc('control_calidad');
      expect(
          await s.registrar(
              area: AreaMerma.calidad, saborId: 1, causas: {'exceso_agua': 5}, cantidadProducida: -1),
          contains('negativo'));
    });
  });
}
