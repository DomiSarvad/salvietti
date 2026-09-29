import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/registro_salidas/models/salidas_modelos.dart';
import 'package:salvietti_control/features/registro_salidas/repositories/salidas_repository.dart';
import 'package:salvietti_control/features/registro_salidas/services/salidas_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements SalidasRepository {
  List<ReporteSalidas> lista;
  ErrorNegocioSalidas? negocio;
  final creados = <String>[];
  final lineasGuardadas = <DatosLinea>[];
  final lineasEliminadas = <int>[];
  final cerrados = <int>[];

  _Repo([List<ReporteSalidas>? lista]) : lista = lista ?? [];

  @override
  Future<List<Sabor>> sabores() async =>
      const [Sabor(id: 1, nombre: 'Papaya'), Sabor(id: 2, nombre: 'Ross')];

  @override
  Future<List<Presentacion>> presentaciones() async => const [
        Presentacion(id: 10, nombre: '2.5 L', material: 'pet'),
        Presentacion(id: 11, nombre: '1 L', material: 'vidrio'),
      ];

  @override
  Future<Set<int>> presentacionesDe(int saborId) async => saborId == 1 ? {10, 11} : {11};

  @override
  Future<List<ReporteSalidas>> reportes({int limite = 60}) async => lista;

  @override
  Future<List<LineaSalidas>> lineasDe(int reporteId) async => const [];

  @override
  Future<List<PlanillaFila>> planilla({int limite = 60}) async => [
        PlanillaFila(fecha: DateTime(2026, 9, 22), sabor: 'Papaya', presentacion: '2.5 L',
            material: 'pet', reportes: 1, totalBotellas: 3400)
      ];

  @override
  Future<int> crearReporte(String turno) async {
    if (negocio != null) throw negocio!;
    creados.add(turno);
    return 1;
  }

  @override
  Future<int> guardarLinea(int reporteId, DatosLinea d) async {
    if (negocio != null) throw negocio!;
    lineasGuardadas.add(d);
    return 1;
  }

  @override
  Future<void> eliminarLinea(int idLinea) async {
    if (negocio != null) throw negocio!;
    lineasEliminadas.add(idLinea);
  }

  @override
  Future<void> cerrarReporte(int id, String? observaciones) async {
    if (negocio != null) throw negocio!;
    cerrados.add(id);
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'registro_salidas':
      return {'salidas:ver', 'salidas:crear', 'salidas:editar'};
    case 'jefe_produccion':
      return {'salidas:ver'};
    default:
      return {};
  }
}

ReporteSalidas _reporte({
  int id = 1,
  EstadoReporte estado = EstadoReporte.abierto,
}) =>
    ReporteSalidas(
      id: id, fecha: DateTime(2026, 9, 22), turno: Turno.manana,
      horaInicioDia: DateTime(2026, 9, 22, 6), estado: estado,
    );

Future<SalidasService> _svc(String rol, [_Repo? repo]) async {
  final s = SalidasService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('control_calidad');
      expect(s.puedeVer, isFalse);
      expect(s.reportes, isEmpty);
    });

    test('Jefe de Producción ve la planilla pero no puede crear ni editar', () async {
      final s = await _svc('jefe_produccion');
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(s.planilla.single.totalBotellas, 3400);
      expect(await s.crearReporte('manana'), contains('permiso'));
    });
  });

  group('crear reporte', () {
    test('exige turno', () async {
      final s = await _svc('registro_salidas');
      expect(await s.crearReporte(null), contains('turno'));
    });

    test('crea y traduce el error del servidor (ya existe)', () async {
      final repo = _Repo();
      final s = await _svc('registro_salidas', repo);
      expect(await s.crearReporte('tarde'), isNull);
      expect(repo.creados, ['tarde']);

      repo.negocio = const ErrorNegocioSalidas('Ya existe un reporte de hoy para ese turno.');
      expect(await s.crearReporte('tarde'), 'Ya existe un reporte de hoy para ese turno.');
    });
  });

  group('guardar línea', () {
    const datos = DatosLinea(saborId: 1, presentacionId: 10, petPalets: 5);

    test('solo quien puede editar, y solo si el reporte está abierto', () async {
      final jefe = await _svc('jefe_produccion');
      expect(await jefe.guardarLinea(_reporte(), datos), contains('permiso'));

      final salidas = await _svc('registro_salidas');
      expect(
          await salidas.guardarLinea(_reporte(estado: EstadoReporte.cerrado), datos),
          contains('cerrado'));
    });

    test('rechaza valores negativos', () async {
      final s = await _svc('registro_salidas');
      expect(
          await s.guardarLinea(_reporte(),
              const DatosLinea(saborId: 1, presentacionId: 10, petBotellasLibres: -1)),
          contains('negativo'));
    });

    test('guarda cuando está todo bien', () async {
      final repo = _Repo();
      final s = await _svc('registro_salidas', repo);
      expect(await s.guardarLinea(_reporte(), datos), isNull);
      expect(repo.lineasGuardadas.single.petPalets, 5);
    });
  });

  group('cerrar reporte', () {
    test('exige que esté abierto', () async {
      final repo = _Repo();
      final s = await _svc('registro_salidas', repo);
      expect(
          await s.cerrarReporte(_reporte(estado: EstadoReporte.cerrado), null),
          contains('cerrado'));
      expect(await s.cerrarReporte(_reporte(), 'Todo conforme'), isNull);
      expect(repo.cerrados, [1]);
    });
  });
}
