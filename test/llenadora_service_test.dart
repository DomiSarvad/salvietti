import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/llenadora/models/llenadora_modelos.dart';
import 'package:salvietti_control/features/llenadora/repositories/llenadora_repository.dart';
import 'package:salvietti_control/features/llenadora/services/llenadora_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements LlenadoraRepository {
  List<CorridaLlenadora> lista;
  ErrorNegocioLlenadora? negocio;
  final iniciadas = <Map<String, dynamic>>[];
  final finalizadas = <FinalizarCorridaLlenadora>[];
  final anuladas = <int>[];

  _Repo([List<CorridaLlenadora>? lista]) : lista = lista ?? [];

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
  Future<List<PreparadoJarabes>> preparadosDe(int saborId) async =>
      [const PreparadoJarabes(id: 1, saborId: 1, nLote: 3, tanque: 2)];

  @override
  Future<List<ItemInventario>> tapas({String? busqueda}) async =>
      const [ItemInventario(id: 1, codigo: 'IN-0010', detalle: 'Tapa Short Negro', unidad: 'PZA')];

  @override
  Future<List<CorridaLlenadora>> corridas({int limite = 200}) async => lista;

  @override
  Future<List<AvanceLlenadora>> avance() async => const [
        AvanceLlenadora(sabor: 'Papaya', presentacion: '2.5 L', corridas: 1, botellasBuenas: 3400),
      ];

  @override
  Future<int> iniciarCorrida({
    required String turno,
    required int saborId,
    required int presentacionId,
    int? preparadoId,
    String? nLotePreparado,
    String? tanque,
    int? itemTapaId,
  }) async {
    if (negocio != null) throw negocio!;
    iniciadas.add({
      'turno': turno, 'sabor': saborId, 'presentacion': presentacionId,
      'preparado': preparadoId, 'lote': nLotePreparado, 'tanque': tanque, 'tapa': itemTapaId,
    });
    return 9;
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorridaLlenadora d) async {
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
    case 'llenadora':
      return {'llenado:ver', 'llenado:crear', 'llenado:editar'};
    case 'jefe_produccion':
      return {'llenado:ver'};
    default:
      return {};
  }
}

CorridaLlenadora _corrida({
  int id = 1,
  EstadoCorrida estado = EstadoCorrida.enCurso,
}) =>
    CorridaLlenadora(
      id: id, fecha: DateTime(2026, 9, 22), turno: Turno.manana, saborId: 1, presentacionId: 10,
      estado: estado, horaInicio: DateTime(2026, 9, 22, 8),
    );

Future<LlenadoraService> _svc(String rol, [_Repo? repo]) async {
  final s = LlenadoraService(repo ?? _Repo(), _usuario(rol));
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
      final s = await _svc('llenadora');
      expect(await s.iniciarCorrida(turno: null, saborId: 1, presentacionId: 10),
          contains('turno'));
      expect(await s.iniciarCorrida(turno: 'manana', saborId: null, presentacionId: 10),
          contains('sabor'));
      expect(await s.iniciarCorrida(turno: 'manana', saborId: 1, presentacionId: null),
          contains('presentación'));
    });

    test('crea con preparado y tapa, y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('llenadora', repo);
      expect(
          await s.iniciarCorrida(
              turno: 'tarde', saborId: 1, presentacionId: 10, preparadoId: 3, itemTapaId: 1),
          isNull);
      expect(repo.iniciadas.single,
          {'turno': 'tarde', 'sabor': 1, 'presentacion': 10, 'preparado': 3, 'lote': null, 'tanque': null, 'tapa': 1});

      repo.negocio = const ErrorNegocioLlenadora('Ese sabor no se fabrica en esa presentación.');
      expect(await s.iniciarCorrida(turno: 'manana', saborId: 1, presentacionId: 99),
          'Ese sabor no se fabrica en esa presentación.');
    });
  });

  group('finalizar corrida', () {
    const base = FinalizarCorridaLlenadora(botellasLlenadas: 3400);

    test('solo quien puede editar, y solo si está en curso', () async {
      final jefe = await _svc('jefe_produccion');
      expect(await jefe.finalizarCorrida(_corrida(), base), contains('permiso'));

      final llenadora = await _svc('llenadora');
      expect(
          await llenadora.finalizarCorrida(_corrida(estado: EstadoCorrida.finalizada), base),
          contains('ya se cerró'));
    });

    test('rechaza cantidades negativas', () async {
      final s = await _svc('llenadora');
      expect(
          await s.finalizarCorrida(
              _corrida(), const FinalizarCorridaLlenadora(botellasLlenadas: -1)),
          contains('negativa'));
    });

    test('exige motivo cuando hay cualquier merma', () async {
      final s = await _svc('llenadora');
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorridaLlenadora(botellasLlenadas: 3400, rebalse: 5)),
          contains('motivo de la merma'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorridaLlenadora(
                  botellasLlenadas: 3400, rebalse: 5, motivoMerma: 'Válvula floja')),
          isNull);
    });

    test('finaliza sin problema cuando no hubo merma', () async {
      final repo = _Repo();
      final s = await _svc('llenadora', repo);
      expect(await s.finalizarCorrida(_corrida(), base), isNull);
      expect(repo.finalizadas.single.botellasLlenadas, 3400);
    });
  });

  group('anular corrida', () {
    test('exige motivo y que esté en curso', () async {
      final repo = _Repo();
      final s = await _svc('llenadora', repo);
      expect(await s.anularCorrida(_corrida(), 'x'), contains('mínimo 3'));
      expect(
          await s.anularCorrida(_corrida(estado: EstadoCorrida.finalizada), 'Error de carga'),
          contains('en curso'));
      expect(await s.anularCorrida(_corrida(), 'Sabor equivocado'), isNull);
      expect(repo.anuladas, [1]);
    });
  });
}
