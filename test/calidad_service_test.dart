import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/calidad/models/calidad_modelos.dart';
import 'package:salvietti_control/features/calidad/repositories/calidad_repository.dart';
import 'package:salvietti_control/features/calidad/services/calidad_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements CalidadRepository {
  List<PreparadoPendiente> pendientesFijos;
  List<AnalisisCalidad> analisisFijos;
  bool fallar = false;
  ErrorNegocioCalidad? negocio;

  final registrados = <NuevoAnalisis>[];
  final actualizados = <int>[];

  _Repo({List<PreparadoPendiente>? pendientes, List<AnalisisCalidad>? analisis})
      : pendientesFijos = pendientes ?? [],
        analisisFijos = analisis ?? [];

  @override
  Future<List<PreparadoPendiente>> pendientes() async {
    if (fallar) throw Exception('sin conexión');
    return pendientesFijos;
  }

  @override
  Future<List<AnalisisCalidad>> analisis({int limite = 200}) async => analisisFijos;

  @override
  Future<int> registrarAnalisis(NuevoAnalisis a) async {
    if (negocio != null) throw negocio!;
    registrados.add(a);
    return 7;
  }

  @override
  Future<void> actualizarAnalisis(int id, {String? accionTomada, String? observaciones}) async {
    if (negocio != null) throw negocio!;
    actualizados.add(id);
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'control_calidad':
      return {'calidad:ver', 'calidad:crear', 'calidad:editar'};
    case 'jefe_produccion':
      return {'calidad:ver'};
    default:
      return {};
  }
}

PreparadoPendiente _pendiente({double? brix = 12, double? brixMin, double? brixMax}) =>
    PreparadoPendiente(
      preparadoId: 1, fecha: DateTime(2026, 9, 22), sabor: 'Papaya', nLote: 27,
      cantidadPreparados: 2, brix: brix, brixMin: brixMin, brixMax: brixMax,
    );

AnalisisCalidad _analisis({int id = 1}) => AnalisisCalidad(
      id: id, preparadoId: 1, fecha: DateTime(2026, 9, 22), resultado: 'conforme',
    );

Future<CalidadService> _svc(String rol, [_Repo? repo]) async {
  final s = CalidadService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

const _validos = NuevoAnalisis(preparadoId: 1, brixDiluido: 5.2, ph: 3.4, resultado: 'conforme');

void main() {
  group('permisos', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('almacen');
      expect(s.puedeVer, isFalse);
      expect(s.pendientes, isEmpty);
    });

    test('Jefe de Producción ve pero no registra', () async {
      final repo = _Repo(pendientes: [_pendiente()]);
      final s = await _svc('jefe_produccion', repo);
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(s.pendientes, hasLength(1));
      expect(await s.registrarAnalisis(_validos), contains('permiso'));
    });
  });

  group('rango de Brix', () {
    test('detecta cuando el Brix de Jarabes está fuera del rango del sabor', () {
      expect(_pendiente(brix: 10, brixMin: 12, brixMax: 14).brixFueraDeRango, isTrue);
      expect(_pendiente(brix: 13, brixMin: 12, brixMax: 14).brixFueraDeRango, isFalse);
      expect(_pendiente(brix: 13, brixMin: null, brixMax: null).brixFueraDeRango, isFalse);
    });
  });

  group('registrar análisis', () {
    test('exige Brix y pH válidos', () async {
      final s = await _svc('control_calidad');
      expect(await s.registrarAnalisis(const NuevoAnalisis(preparadoId: 1, resultado: 'conforme')),
          contains('Brix'));
      expect(
          await s.registrarAnalisis(
              const NuevoAnalisis(preparadoId: 1, brixDiluido: 5, resultado: 'conforme')),
          contains('pH'));
      expect(
          await s.registrarAnalisis(
              const NuevoAnalisis(preparadoId: 1, brixDiluido: 5, ph: 20, resultado: 'conforme')),
          contains('pH'));
    });

    test('exige acción tomada cuando no es conforme', () async {
      final repo = _Repo();
      final s = await _svc('control_calidad', repo);
      expect(
          await s.registrarAnalisis(const NuevoAnalisis(
              preparadoId: 1, brixDiluido: 5, ph: 3.5, resultado: 'no_conforme')),
          contains('acción'));
      expect(
          await s.registrarAnalisis(const NuevoAnalisis(
              preparadoId: 1, brixDiluido: 5, ph: 3.5, resultado: 'no_conforme',
              accionTomada: 'Se descartó el lote')),
          isNull);
      expect(repo.registrados, hasLength(1));
    });

    test('registra un análisis válido y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('control_calidad', repo);
      expect(await s.registrarAnalisis(_validos), isNull);
      expect(repo.registrados.single.brixDiluido, 5.2);

      repo.negocio = const ErrorNegocioCalidad('Ese preparado ya tiene un análisis registrado.');
      expect(await s.registrarAnalisis(_validos), 'Ese preparado ya tiene un análisis registrado.');
    });
  });

  group('actualizar análisis', () {
    test('solo quien puede editar', () async {
      final repo = _Repo();
      final jefe = await _svc('jefe_produccion', repo);
      expect(await jefe.actualizarAnalisis(_analisis(), accionTomada: 'x'), contains('permiso'));

      final calidad = await _svc('control_calidad', repo);
      expect(await calidad.actualizarAnalisis(_analisis(), accionTomada: 'Se repuso el lote'),
          isNull);
      expect(repo.actualizados, [1]);
    });
  });
}
