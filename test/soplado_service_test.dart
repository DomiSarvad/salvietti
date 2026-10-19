import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/soplado/models/soplado_modelos.dart';
import 'package:salvietti_control/features/soplado/repositories/soplado_repository.dart';
import 'package:salvietti_control/features/soplado/services/soplado_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements SopladoRepository {
  void Function()? alCambiar; // simula un aviso de Realtime

  @override
  Suscripcion escucharCambios(void Function() onCambio) {
    alCambiar = onCambio;
    return const SuscripcionNula();
  }

  List<CorridaSoplado> lista;
  bool fallar = false;
  ErrorNegocioSoplado? negocio;
  final iniciadas = <Map<String, dynamic>>[];
  final finalizadas = <FinalizarCorrida>[];
  final anuladas = <int>[];

  _Repo([List<CorridaSoplado>? lista]) : lista = lista ?? [];

  @override
  Future<List<Sabor>> sabores() async =>
      const [Sabor(id: 1, nombre: 'Papaya'), Sabor(id: 2, nombre: 'Ross')];

  @override
  Future<List<Presentacion>> presentacionesPet() async => const [
        Presentacion(id: 10, nombre: '2.5 L', material: 'pet'),
        Presentacion(id: 11, nombre: '2 L', material: 'pet'),
      ];

  @override
  Future<Set<int>> presentacionesDe(int saborId) async =>
      saborId == 1 ? {10, 11} : {11};

  @override
  Future<List<ItemPreforma>> preformas({String? busqueda}) async =>
      const [ItemPreforma(id: 1, codigo: 'IN-0001', detalle: 'Preforma 2.5L', unidad: 'PZA')];

  @override
  Future<List<Proveedor>> proveedores({String? busqueda}) async =>
      const [Proveedor(id: 1, nombre: 'Ambar Plast')];

  @override
  Future<List<CorridaSoplado>> corridas({int limite = 200}) async {
    if (fallar) throw Exception('sin conexión');
    return lista;
  }

  @override
  Future<List<AvanceSoplado>> avance() async => const [
        AvanceSoplado(sabor: 'Papaya', presentacion: '2.5 L', corridas: 1, botellasBuenas: 3470),
      ];

  @override
  Future<int> iniciarCorrida({
    required int saborId,
    required int presentacionId,
    int? itemPreformaId,
    int? proveedorId,
    String? lotePreforma,
  }) async {
    if (negocio != null) throw negocio!;
    iniciadas.add({
      'sabor': saborId, 'presentacion': presentacionId, 'preforma': itemPreformaId,
      'proveedor': proveedorId, 'lote': lotePreforma,
    });
    return 5;
  }

  @override
  Future<void> finalizarCorrida(int id, FinalizarCorrida d) async {
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
    case 'soplado':
      return {'soplado:ver', 'soplado:crear', 'soplado:editar'};
    case 'jarabes':
      return {'soplado:ver'};
    default:
      return {};
  }
}

CorridaSoplado _corrida({
  int id = 1,
  EstadoCorrida estado = EstadoCorrida.enCurso,
  String? itemPreformaDetalle,
}) =>
    CorridaSoplado(
      id: id, fecha: DateTime(2026, 9, 22), saborId: 1, presentacionId: 10,
      estado: estado, horaInicio: DateTime(2026, 9, 22, 8), itemPreformaDetalle: itemPreformaDetalle,
    );

Future<SopladoService> _svc(String rol, [_Repo? repo]) async {
  final s = SopladoService(repo ?? _Repo(), _usuario(rol));
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

    test('Jarabes ve el avance pero no puede iniciar ni finalizar', () async {
      final s = await _svc('jarabes');
      expect(s.puedeVer, isTrue);
      expect(s.puedeCrear, isFalse);
      expect(s.avance.single.botellasBuenas, 3470);
      expect(await s.iniciarCorrida(saborId: 1, presentacionId: 10), contains('permiso'));
    });
  });

  group('iniciar corrida', () {
    test('exige sabor y presentación', () async {
      final s = await _svc('soplado');
      expect(await s.iniciarCorrida(saborId: null, presentacionId: 10), contains('sabor'));
      expect(await s.iniciarCorrida(saborId: 1, presentacionId: null), contains('presentación'));
    });

    test('crea con preforma, proveedor y lote, y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('soplado', repo);
      expect(
          await s.iniciarCorrida(
              saborId: 1, presentacionId: 10, itemPreformaId: 7, proveedorId: 3, lotePreforma: '2096'),
          isNull);
      expect(repo.iniciadas.single,
          {'sabor': 1, 'presentacion': 10, 'preforma': 7, 'proveedor': 3, 'lote': '2096'});

      repo.negocio = const ErrorNegocioSoplado('Ese sabor no se fabrica en esa presentación.');
      expect(await s.iniciarCorrida(saborId: 1, presentacionId: 99),
          'Ese sabor no se fabrica en esa presentación.');
    });

    test('la matriz sabor × presentación limita las opciones', () async {
      final s = await _svc('soplado');
      expect(await s.presentacionesDe(1), {10, 11});
      expect(await s.presentacionesDe(2), {11});
    });
  });

  group('finalizar corrida', () {
    const base = FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 5);

    test('solo quien puede editar, y solo si está en curso', () async {
      final jarabes = await _svc('jarabes');
      expect(await jarabes.finalizarCorrida(_corrida(), base), contains('permiso'));

      final soplado = await _svc('soplado');
      expect(
          await soplado.finalizarCorrida(_corrida(estado: EstadoCorrida.finalizada), base),
          contains('ya se cerró'));
    });

    test('rechaza cantidades negativas y mermas por encima de lo producido/usado', () async {
      final s = await _svc('soplado');
      expect(
          await s.finalizarCorrida(
              _corrida(), const FinalizarCorrida(botellasSopladas: -1, preformasUsadas: 5)),
          contains('negativa'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 5, mermaPreforma: 10)),
          contains('más preformas de las que se usaron'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 6, mermaSoplado: 10)),
          contains('merma de soplado no puede ser mayor'));
    });

    test('exige motivo cuando hay cualquiera de las tres mermas', () async {
      final s = await _svc('soplado');
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 6, mermaEtiquetado: 1)),
          contains('motivo de la merma'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 6, mermaEtiquetado: 1,
                  motivoMerma: 'Etiqueta corrida')),
          isNull);
    });

    test('exige motivo cuando hay tiempo de parada', () async {
      final s = await _svc('soplado');
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 5, tiempoParadaMinutos: 15)),
          contains('motivo de la parada'));
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 5, preformasUsadas: 5, tiempoParadaMinutos: 15,
                  motivoParada: 'Corte de energía')),
          isNull);
    });

    test('finaliza sin problema cuando no hubo merma ni parada', () async {
      final repo = _Repo();
      final s = await _svc('soplado', repo);
      expect(
          await s.finalizarCorrida(_corrida(),
              const FinalizarCorrida(botellasSopladas: 3500, preformasUsadas: 3500, botellasEtiquetadas: 3485)),
          isNull);
      expect(repo.finalizadas.single.botellasSopladas, 3500);
    });
  });

  group('anular corrida', () {
    test('exige motivo y que esté en curso', () async {
      final repo = _Repo();
      final s = await _svc('soplado', repo);
      expect(await s.anularCorrida(_corrida(), 'x'), contains('mínimo 3'));
      expect(
          await s.anularCorrida(_corrida(estado: EstadoCorrida.finalizada), 'Error de carga'),
          contains('en curso'));
      expect(await s.anularCorrida(_corrida(), 'Sabor equivocado'), isNull);
      expect(repo.anuladas, [1]);
    });
  });

  group('tiempo real', () {
    test('un cambio de otra persona recarga solo, sin spinner ni error', () async {
      final repo = _Repo();
      final s = await _svc('soplado', repo);
      expect(s.corridas, isEmpty);
      var vecesCargando = 0;
      s.addListener(() {
        if (s.cargando) vecesCargando++;
      });

      repo.lista = [_corrida()];
      repo.alCambiar!();
      repo.alCambiar!(); // dos avisos seguidos: una sola recarga
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(s.corridas, hasLength(1));
      expect(vecesCargando, 0);

      // Si la recarga en segundo plano falla, se siguen viendo los datos.
      repo.fallar = true;
      repo.alCambiar!();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(s.error, isNull);
      expect(s.corridas, hasLength(1));
      s.dispose();
    });
  });
}
