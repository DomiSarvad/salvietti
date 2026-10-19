import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/jarabes/models/jarabes_modelos.dart';
import 'package:salvietti_control/features/jarabes/repositories/jarabes_repository.dart';
import 'package:salvietti_control/features/jarabes/services/jarabes_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements JarabesRepository {
  @override
  Suscripcion escucharCambios(void Function() onCambio) => const SuscripcionNula();

  List<Preparado> preparadosFijos;
  List<RecetaPropuesta> pendientesFijas;
  bool fallar = false;
  ErrorNegocioJarabes? negocio;

  final recetasCreadas = <Map<int, double>>[];
  final aprobadasCalidad = <int>[];
  final aprobadasProduccion = <int>[];
  final confirmadasGerente = <Map<String, dynamic>>[];
  final rechazadas = <int>[];
  final iniciadas = <Map<String, dynamic>>[];
  final finalizadas = <int>[];
  final anuladas = <int>[];
  final pedidos = <Map<int, double>>[];

  _Repo({List<Preparado>? preparados, List<RecetaPropuesta>? pendientes})
      : preparadosFijos = preparados ?? [],
        pendientesFijas = pendientes ?? [];

  @override
  Future<List<Sabor>> sabores() async =>
      const [Sabor(id: 1, nombre: 'Papaya'), Sabor(id: 2, nombre: 'Naranja')];

  @override
  Future<List<ItemJarabes>> itemsJarabes({String? busqueda}) async =>
      const [ItemJarabes(id: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG')];

  @override
  Future<List<ItemReceta>> recetaVigente(int saborId) async => const [];

  @override
  Future<List<RecetaPropuesta>> recetasPendientes() async {
    if (fallar) throw Exception('sin conexión');
    return pendientesFijas;
  }

  @override
  Future<List<Preparado>> preparados({int limite = 200}) async {
    if (fallar) throw Exception('sin conexión');
    return preparadosFijos;
  }

  @override
  Future<List<AvanceSopladoLite>> avanceSoplado() async =>
      const [AvanceSopladoLite(sabor: 'Papaya', presentacion: '2.5 L', cajasSopladas: 6)];

  @override
  Future<int> recetaCrear(int saborId, Map<int, double> items) async {
    if (negocio != null) throw negocio!;
    recetasCreadas.add(items);
    return 9;
  }

  @override
  Future<void> recetaAprobarCalidad(int id) async {
    if (negocio != null) throw negocio!;
    aprobadasCalidad.add(id);
  }

  @override
  Future<void> recetaAprobarProduccion(int id) async {
    if (negocio != null) throw negocio!;
    aprobadasProduccion.add(id);
  }

  @override
  Future<void> recetaConfirmarGerente(int id, String clave) async {
    if (negocio != null) throw negocio!;
    confirmadasGerente.add({'id': id, 'clave': clave});
  }

  @override
  Future<void> recetaRechazar(int id, String motivo) async {
    if (negocio != null) throw negocio!;
    rechazadas.add(id);
  }

  @override
  Future<List<VerificacionInsumo>> verificarInsumos(int saborId, double cantidad) async {
    if (negocio != null) throw negocio!;
    return [
      VerificacionInsumo(
          itemId: 1, detalle: 'Azúcar', unidad: 'KG',
          necesario: 18 * cantidad, disponible: 20, falta: (18 * cantidad - 20).clamp(0, double.infinity)),
    ];
  }

  @override
  Future<int> iniciarPreparado({required int saborId, required double cantidad, int? tanque}) async {
    if (negocio != null) throw negocio!;
    iniciadas.add({'sabor': saborId, 'cantidad': cantidad, 'tanque': tanque});
    return 3;
  }

  @override
  Future<void> finalizarPreparado(int id, {required double brix, String? observaciones}) async {
    if (negocio != null) throw negocio!;
    finalizadas.add(id);
  }

  @override
  Future<void> anularPreparado(int id, String motivo) async {
    if (negocio != null) throw negocio!;
    anuladas.add(id);
  }

  @override
  Future<void> pedirFaltantes(Map<int, double> itemsYCantidad) async {
    if (negocio != null) throw negocio!;
    pedidos.add(itemsYCantidad);
  }
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'jarabes':
      return {
        'jarabes_produccion:ver', 'jarabes_produccion:crear', 'jarabes_produccion:editar',
        'recetas:ver', 'recetas:crear',
      };
    case 'jefe_produccion':
      return {'jarabes_produccion:ver', 'recetas:ver', 'recetas:aprobar'};
    case 'control_calidad':
      return {'recetas:ver', 'recetas:aprobar'};
    case 'gerente':
      return {'recetas:ver', 'recetas:aprobar'};
    default:
      return {};
  }
}

Preparado _preparado({
  int id = 1,
  EstadoPreparado estado = EstadoPreparado.enCurso,
}) =>
    Preparado(
      id: id, fecha: DateTime(2026, 9, 22), saborId: 1, sabor: 'Papaya', nLote: 27,
      cantidadPreparados: 2, estado: estado, horaInicio: DateTime(2026, 9, 22, 8),
    );

RecetaPropuesta _receta({
  int id = 1,
  EstadoReceta estado = EstadoReceta.propuesta,
  bool aprobadaCalidad = false,
  bool aprobadaProduccion = false,
}) =>
    RecetaPropuesta(
      id: id, saborId: 1, sabor: 'Papaya', estado: estado, creadaEn: DateTime(2026, 9, 22),
      aprobadaCalidadNombre: aprobadaCalidad ? 'Ana Calidad' : null,
      aprobadaCalidadEn: aprobadaCalidad ? DateTime(2026, 9, 23) : null,
      aprobadaProduccionNombre: aprobadaProduccion ? 'Beto Producción' : null,
      aprobadaProduccionEn: aprobadaProduccion ? DateTime(2026, 9, 23) : null,
    );

Future<JarabesService> _svc(String rol, [_Repo? repo]) async {
  final s = JarabesService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver Producción no carga nada', () async {
      final s = await _svc('control_calidad');
      expect(s.puedeVerProduccion, isFalse);
      expect(s.preparados, isEmpty);
    });

    test('Jefe de Producción aprueba pero no inicia ni propone', () async {
      final repo = _Repo(pendientes: [_receta()]);
      final s = await _svc('jefe_produccion', repo);
      expect(s.puedeAprobarReceta, isTrue);
      expect(s.puedeProponerReceta, isFalse);
      expect(s.puedeIniciar, isFalse);
      expect(s.recetasPendientes, hasLength(1)); // solo se cargan si puede aprobar
    });

    test('Jarabes propone e inicia pero no ve pendientes de aprobar', () async {
      final repo = _Repo(pendientes: [_receta()]);
      final s = await _svc('jarabes', repo);
      expect(s.puedeProponerReceta, isTrue);
      expect(s.puedeIniciar, isTrue);
      expect(s.puedeAprobarReceta, isFalse);
      expect(s.recetasPendientes, isEmpty); // no se piden si no puede aprobar
    });
  });

  group('bandejas', () {
    test('separa en curso de historial', () async {
      final repo = _Repo(preparados: [
        _preparado(id: 1, estado: EstadoPreparado.enCurso),
        _preparado(id: 2, estado: EstadoPreparado.finalizada),
        _preparado(id: 3, estado: EstadoPreparado.anulada),
      ]);
      final s = await _svc('jarabes', repo);
      expect(s.enCurso.map((p) => p.id), [1]);
      expect(s.historial.map((p) => p.id), [2, 3]);
    });
  });

  group('proponer receta', () {
    test('exige permiso, sabor e insumos válidos', () async {
      final repo = _Repo();
      final sinPermiso = await _svc('jefe_produccion', repo);
      expect(await sinPermiso.proponerReceta(1, {1: 5}), contains('permiso'));

      final s = await _svc('jarabes', repo);
      expect(await s.proponerReceta(null, {1: 5}), contains('sabor'));
      expect(await s.proponerReceta(1, {}), contains('insumo'));
      expect(await s.proponerReceta(1, {1: 0}), contains('mayor a cero'));
      expect(repo.recetasCreadas, isEmpty);

      expect(await s.proponerReceta(1, {1: 18}), isNull);
      expect(repo.recetasCreadas.single, {1: 18.0});
    });
  });

  group('aprobar / rechazar receta (doble aprobación + clave del Gerente)', () {
    test('cada visto bueno es exclusivo de su rol, y solo si está propuesta', () async {
      final repo = _Repo();
      final jarabes = await _svc('jarabes', repo);
      expect(await jarabes.aprobarComoCalidad(_receta()), contains('Control de Calidad'));

      final jefe = await _svc('jefe_produccion', repo);
      expect(await jefe.aprobarComoCalidad(_receta()), contains('Control de Calidad'));
      expect(await jefe.aprobarComoProduccion(_receta(estado: EstadoReceta.activa)),
          contains('ya fue resuelta'));
      expect(await jefe.aprobarComoProduccion(_receta()), isNull);
      expect(repo.aprobadasProduccion, [1]);

      final calidad = await _svc('control_calidad', repo);
      expect(await calidad.aprobarComoProduccion(_receta()), contains('Jefe de Producción'));
      expect(await calidad.aprobarComoCalidad(_receta()), isNull);
      expect(repo.aprobadasCalidad, [1]);
    });

    test('no deja dar el mismo visto bueno dos veces', () async {
      final calidad = await _svc('control_calidad');
      expect(await calidad.aprobarComoCalidad(_receta(aprobadaCalidad: true)),
          contains('ya dio su visto bueno'));
    });

    test('el Gerente solo confirma con las dos aprobaciones y su clave', () async {
      final gerente = await _svc('gerente');
      expect(await gerente.confirmarComoGerente(_receta(), 'clave123'),
          contains('falta el visto bueno de Control de Calidad'));
      expect(
          await gerente.confirmarComoGerente(_receta(aprobadaCalidad: true), 'clave123'),
          contains('falta el visto bueno de Jefe de Producción'));
      expect(
          await gerente.confirmarComoGerente(
              _receta(aprobadaCalidad: true, aprobadaProduccion: true), ''),
          contains('clave'));

      final jefe = await _svc('jefe_produccion');
      expect(
          await jefe.confirmarComoGerente(
              _receta(aprobadaCalidad: true, aprobadaProduccion: true), 'clave123'),
          contains('Solo el Gerente'));

      final repo = _Repo();
      final s = await _svc('gerente', repo);
      expect(
          await s.confirmarComoGerente(
              _receta(aprobadaCalidad: true, aprobadaProduccion: true), 'clave123'),
          isNull);
      expect(repo.confirmadasGerente.single, {'id': 1, 'clave': 'clave123'});

      repo.negocio = const ErrorNegocioJarabes('Clave incorrecta.');
      expect(
          await s.confirmarComoGerente(
              _receta(aprobadaCalidad: true, aprobadaProduccion: true), 'mala'),
          'Clave incorrecta.');
    });

    test('rechazar exige motivo, y lo puede hacer cualquiera de los tres roles', () async {
      final repo = _Repo();
      final jefe = await _svc('jefe_produccion', repo);
      expect(await jefe.rechazarReceta(_receta(), ''), contains('motivo'));
      expect(await jefe.rechazarReceta(_receta(), 'Falta un insumo'), isNull);
      expect(repo.rechazadas, [1]);
    });
  });

  group('iniciar preparado', () {
    test('exige sabor y cantidad', () async {
      final s = await _svc('jarabes');
      expect(await s.iniciarPreparado(saborId: null, cantidad: 2), contains('sabor'));
      expect(await s.iniciarPreparado(saborId: 1, cantidad: 0), contains('mayor a cero'));
      expect(await s.iniciarPreparado(saborId: 1, cantidad: 2, tanque: -1), contains('tanque'));
    });

    test('inicia y traduce el error del servidor cuando falta stock', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      expect(await s.iniciarPreparado(saborId: 1, cantidad: 2, tanque: 3), isNull);
      expect(repo.iniciadas.single, {'sabor': 1, 'cantidad': 2.0, 'tanque': 3});

      repo.negocio = const ErrorNegocioJarabes('No alcanza el stock de "Azúcar": faltan 5 KG.');
      expect(await s.iniciarPreparado(saborId: 1, cantidad: 5),
          'No alcanza el stock de "Azúcar": faltan 5 KG.');
    });

    test('la verificación de insumos calcula lo que falta', () async {
      final s = await _svc('jarabes');
      final r = await s.verificarInsumos(1, 2);
      expect(r.single.necesario, 36);
      expect(r.single.alcanza, isFalse);
    });
  });

  group('pedir faltantes', () {
    test('solo pide lo que realmente falta', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      const items = [
        VerificacionInsumo(itemId: 1, detalle: 'A', unidad: 'KG', necesario: 10, disponible: 10, falta: 0),
        VerificacionInsumo(itemId: 2, detalle: 'B', unidad: 'KG', necesario: 10, disponible: 4, falta: 6),
      ];
      expect(await s.pedirFaltantes(items), isNull);
      expect(repo.pedidos.single, {2: 6.0});
    });

    test('sin faltantes no pide nada', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      const items = [
        VerificacionInsumo(itemId: 1, detalle: 'A', unidad: 'KG', necesario: 10, disponible: 10, falta: 0),
      ];
      expect(await s.pedirFaltantes(items), contains('No hay faltantes'));
      expect(repo.pedidos, isEmpty);
    });
  });

  group('finalizar / anular preparado', () {
    test('exige Brix válido y solo si está en curso', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      expect(await s.finalizarPreparado(_preparado(), brix: null), contains('Brix'));
      expect(await s.finalizarPreparado(_preparado(), brix: 150), contains('Brix'));
      expect(
          await s.finalizarPreparado(_preparado(estado: EstadoPreparado.finalizada), brix: 12),
          contains('ya se cerró'));
      expect(await s.finalizarPreparado(_preparado(), brix: 12.5), isNull);
      expect(repo.finalizadas, [1]);
    });

    test('anular exige motivo y que esté en curso', () async {
      final repo = _Repo();
      final s = await _svc('jarabes', repo);
      expect(await s.anularPreparado(_preparado(), 'x'), contains('mínimo 3'));
      expect(await s.anularPreparado(_preparado(), 'Sabor equivocado'), isNull);
      expect(repo.anuladas, [1]);
    });
  });
}
