import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/codificacion/models/codificacion_modelos.dart';
import 'package:salvietti_control/features/codificacion/repositories/codificacion_repository.dart';
import 'package:salvietti_control/features/codificacion/services/codificacion_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements CodificacionRepository {
  List<CorridaCodificacion> lista;
  ErrorNegocioCodificacion? negocio;
  final iniciadas = <Map<String, dynamic>>[];
  final finalizadas = <FinalizarCorridaCodificacion>[];
  final anuladas = <int>[];

  _Repo([List<CorridaCodificacion>? lista]) : lista = lista ?? [];

  @override
  Future<List<Sabor>> sabores() async =>
      const [Sabor(id: 1, nombre: 'Papaya'), Sabor(id: 2, nombre: 'Ross')];

  @override
  Future<List<Presentacion>> presentaciones() async => const [
        Presentacion(id: 10, nombre: '2.5 L', material: 'pet'),
      ];

  @override
  Future<Set<int>> presentacionesDe(int saborId) async => saborId == 1 ? {10} : {};

  @override
  Future<List<CorridaLlenadoraRef>> corridasLlenadoraDe(int saborId) async =>
      [const CorridaLlenadoraRef(id: 5, saborId: 1, turno: 'manana')];

  @override
  Future<List<ItemInventario>> items({String? busqueda}) async =>
      const [ItemInventario(id: 1, codigo: 'IN-0020', detalle: 'Solvente codificador', unidad: 'L')];

  @override
  Future<List<CorridaCodificacion>> corridas({int limite = 200}) async => lista;

  @override
  Future<List<AvanceCodificacion>> avance() async => const [
        AvanceCodificacion(sabor: 'Papaya', presentacion: '2.5 L', corridas: 1, botellasBuenas: 3400),
      ];

  @override
  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? corridaLlenadoraId,
    String? nLote,
    int? itemSolventeId,
    int? itemTintaId,
  }) async {
    if (negocio != null) throw negocio!;
    iniciadas.add({
      'turno': turno, 'sabor': saborId, 'presentacion': presentacionId,
      'llenadora': corridaLlenadoraId, 'lote': nLote, 'solvente': itemSolventeId, 'tinta': itemTintaId,
    });
    return 7;
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorridaCodificacion d) async {
    if (negocio != null) throw negocio!;
    finalizadas.add(d);
  }

  @override
  Future<void> anularCorrida(int id, String motivo) async {
    if (negocio != null) throw negocio!;
    anuladas.add(id);
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'codificacion':
      return {'codificacion:ver', 'codificacion:crear', 'codificacion:editar'};
    case 'jefe_produccion':
      return {'codificacion:ver'};
    default:
      return {};
  }
}

CorridaCodificacion _corrida({
  int id = 1,
  EstadoCorrida estado = EstadoCorrida.enCurso,
}) =>
    CorridaCodificacion(
      id: id, fecha: DateTime(2026, 9, 22), turno: Turno.manana, saborId: 1, presentacionId: 10,
      estado: estado, horaInicio: DateTime(2026, 9, 22, 8),
    );

Future<CodificacionService> _svc(String rol, [_Repo? repo]) async {
  final s = CodificacionService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('control_calidad');
      expect(s.puedeVer, isFalse);
      expect(s.corridas, isEmpty);
    });

    test('Jefe de Producción ve el avance pero no puede iniciar ni finalizar', () async {
      final s = await _svc('jefe_produccion');
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(s.avance.single.botellasBuenas, 3400);
      expect(await s.iniciarCorrida(turno: 'manana', saborId: 1, presentacionId: 10),
          contains('permiso'));
    });
  });

  group('iniciar corrida', () {
    test('exige turno, sabor y presentación', () async {
      final s = await _svc('codificacion');
      expect(await s.iniciarCorrida(turno: null, saborId: 1, presentacionId: 10),
          contains('turno'));
      expect(await s.iniciarCorrida(turno: 'manana', saborId: null, presentacionId: 10),
          contains('sabor'));
      expect(await s.iniciarCorrida(turno: 'manana', saborId: 1, presentacionId: null),
          contains('presentación'));
    });

    test('crea con corrida de Llenadora, solvente y tinta, y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('codificacion', repo);
      expect(
          await s.iniciarCorrida(
              turno: 'tarde', saborId: 1, presentacionId: 10,
              corridaLlenadoraId: 5, itemSolventeId: 1, itemTintaId: 2),
          isNull);
      expect(repo.iniciadas.single, {
        'turno': 'tarde', 'sabor': 1, 'presentacion': 10,
        'llenadora': 5, 'lote': null, 'solvente': 1, 'tinta': 2,
      });

      repo.negocio = const ErrorNegocioCodificacion('Ese sabor no se fabrica en esa presentación.');
      expect(await s.iniciarCorrida(turno: 'manana', saborId: 1, presentacionId: 99),
          'Ese sabor no se fabrica en esa presentación.');
    });
  });

  group('finalizar corrida', () {
    const base = FinalizarCorridaCodificacion(botellasCodificadas: 3400);

    test('solo quien puede editar, y solo si está en curso', () async {
      final jefe = await _svc('jefe_produccion');
      expect(await jefe.finalizarCorrida(_corrida(), base), contains('permiso'));

      final codificacion = await _svc('codificacion');
      expect(
          await codificacion.finalizarCorrida(_corrida(estado: EstadoCorrida.finalizada), base),
          contains('ya se cerró'));
    });

    test('rechaza cantidades negativas', () async {
      final s = await _svc('codificacion');
      expect(
          await s.finalizarCorrida(
              _corrida(), const FinalizarCorridaCodificacion(botellasCodificadas: -1)),
          contains('negativa'));
    });

    test('no deja que la merma supere lo codificado', () async {
      final s = await _svc('codificacion');
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorridaCodificacion(botellasCodificadas: 10, botellasMalTapadas: 999)),
          contains('no puede ser mayor a lo codificado'));
    });

    test('exige motivo cuando hay cualquier merma', () async {
      final s = await _svc('codificacion');
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorridaCodificacion(botellasCodificadas: 3400, impurezas: 4)),
          contains('motivo de la merma'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorridaCodificacion(
                  botellasCodificadas: 3400, impurezas: 4, motivoMerma: 'Polvo en la línea')),
          isNull);
    });

    test('finaliza sin problema cuando no hubo merma', () async {
      final repo = _Repo();
      final s = await _svc('codificacion', repo);
      expect(await s.finalizarCorrida(_corrida(), base), isNull);
      expect(repo.finalizadas.single.botellasCodificadas, 3400);
    });
  });

  group('anular corrida', () {
    test('exige motivo y que esté en curso', () async {
      final repo = _Repo();
      final s = await _svc('codificacion', repo);
      expect(await s.anularCorrida(_corrida(), 'x'), contains('mínimo 3'));
      expect(
          await s.anularCorrida(_corrida(estado: EstadoCorrida.finalizada), 'Error de carga'),
          contains('en curso'));
      expect(await s.anularCorrida(_corrida(), 'Sabor equivocado'), isNull);
      expect(repo.anuladas, [1]);
    });
  });
}
