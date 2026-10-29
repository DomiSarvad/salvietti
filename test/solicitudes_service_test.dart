import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/solicitudes/models/solicitud.dart';
import 'package:salvietti_control/features/solicitudes/repositories/solicitudes_repository.dart';
import 'package:salvietti_control/features/solicitudes/services/solicitudes_service.dart';
import 'package:salvietti_control/models/usuario.dart';
import 'package:salvietti_control/features/jarabes/models/jarabes_modelos.dart';

class _Repo implements SolicitudesRepository {
  List<Solicitud> lista;
  bool fallar = false;
  ErrorNegocioSolicitud? negocio;
  SolicitudNueva? ultimaCreada;
  final resueltas = <int>[];

  _Repo([List<Solicitud>? lista]) : lista = lista ?? [];

  @override
  Future<List<Solicitud>> solicitudes({int limite = 300}) async {
    if (fallar) throw Exception('sin conexión');
    return lista;
  }

  @override
  Future<List<ItemReferencia>> items({String? busqueda}) async =>
      const [ItemReferencia(id: 1, codigo: 'MP-0001', detalle: 'Azúcar', unidad: 'KG')];

  @override
  Future<int> crear(SolicitudNueva s) async {
    if (negocio != null) throw negocio!;
    ultimaCreada = s;
    return 42;
  }

  @override
  Future<void> resolver(int id, {required bool aprobar, String? respuesta}) async {
    if (negocio != null) throw negocio!;
    resueltas.add(id);
  }

  List<RecetaPropuesta> recetasFijas = [];

  @override
  Future<List<RecetaPropuesta>> recetas(DateTime desde) async => recetasFijas;
}

Usuario _usuario(String rol) =>
    Usuario(id: 'u1', nombreCompleto: 'Prueba', rol: rol, permisos: _permisosDe(rol));

Set<String> _permisosDe(String rol) {
  switch (rol) {
    case 'almacen':
      return {'solicitudes:ver', 'solicitudes:crear'};
    case 'gerente':
      return {'solicitudes:ver', 'aprobaciones:ver', 'aprobaciones:aprobar'};
    case 'control_calidad':
      return {'solicitudes:ver', 'solicitudes:crear'};
    default:
      return {};
  }
}

Solicitud _solicitud({
  int id = 1,
  EstadoSolicitud estado = EstadoSolicitud.pendiente,
  String solicitante = 'u1',
}) =>
    Solicitud(
      id: id, fecha: DateTime(2026, 9, 21), tipo: TipoSolicitud.suministro,
      asunto: 'Falta ácido cítrico', estado: estado, solicitanteId: solicitante,
      solicitanteNombre: 'Fulano',
    );

Future<SolicitudesService> _svc(String rol, [_Repo? repo]) async {
  final s = SolicitudesService(repo ?? _Repo(), _usuario(rol));
  await s.iniciar();
  return s;
}

void main() {
  group('permisos', () {
    test('sin permiso de ver no carga nada', () async {
      final s = await _svc('jefe_produccion');
      expect(s.puedeVer, isFalse);
      expect(s.solicitudes, isEmpty);
    });

    test('quien no aprueba abre en "Mis solicitudes"; Gerente en "Por aprobar"', () async {
      final almacen = await _svc('almacen');
      expect(almacen.bandeja, BandejaSolicitudes.mias);
      expect(almacen.puedeAprobar, isFalse);

      final gerente = await _svc('gerente');
      expect(gerente.bandeja, BandejaSolicitudes.porAprobar);
      expect(gerente.puedeAprobar, isTrue);
    });

    test('quien no puede aprobar no ve esa bandeja como opción válida de conteo', () async {
      final repo = _Repo([
        _solicitud(id: 1, solicitante: 'otro'),
        _solicitud(id: 2, solicitante: 'u1'),
      ]);
      final s = await _svc('almacen', repo);
      expect(s.visibles.map((x) => x.id), [2]); // "Mis solicitudes": solo la propia
    });
  });

  group('bandejas', () {
    test('agrupa correctamente por dueño, pendientes y resueltas', () async {
      final repo = _Repo([
        _solicitud(id: 1, solicitante: 'u1', estado: EstadoSolicitud.pendiente),
        _solicitud(id: 2, solicitante: 'otro', estado: EstadoSolicitud.pendiente),
        _solicitud(id: 3, solicitante: 'otro', estado: EstadoSolicitud.aprobada),
        _solicitud(id: 4, solicitante: 'otro', estado: EstadoSolicitud.rechazada),
      ]);
      final s = await _svc('gerente', repo);
      expect(s.pendientesDeAprobar, 2);
      expect(s.visibles.map((x) => x.id), [1, 2]); // porAprobar: cualquiera pendiente
      s.elegirBandeja(BandejaSolicitudes.resueltas);
      expect(s.visibles.map((x) => x.id), [3, 4]);
    });

    test('el Gerente no tiene "Mis solicitudes" (no pide); quien pide no tiene "Por aprobar"',
        () async {
      final gerente = await _svc('gerente');
      expect(gerente.bandejas, [BandejaSolicitudes.porAprobar, BandejaSolicitudes.resueltas]);
      gerente.elegirBandeja(BandejaSolicitudes.mias);
      expect(gerente.bandeja, BandejaSolicitudes.porAprobar); // se ignora

      final almacen = await _svc('almacen');
      expect(almacen.bandejas, [BandejaSolicitudes.mias]);
    });

    test('la pestaña Recetas aparece solo con permiso de ver recetas', () async {
      final repo = _Repo()
        ..recetasFijas = [
          RecetaPropuesta(
              id: 1, saborId: 1, sabor: 'Papaya', estado: EstadoReceta.rechazada,
              creadaEn: DateTime(2026, 10, 28), motivoRechazo: 'no'),
        ];
      final u = Usuario(
          id: 'u1', nombreCompleto: 'G', rol: 'gerente',
          permisos: {..._permisosDe('gerente'), 'recetas:ver'});
      final s = SolicitudesService(repo, u);
      await s.iniciar();
      expect(s.bandejas.last, BandejaSolicitudes.recetas);
      s.elegirBandeja(BandejaSolicitudes.recetas);
      expect(s.recetasFiltradas.single.sabor, 'Papaya');
      expect((await _svc('gerente', repo)).bandejas.contains(BandejaSolicitudes.recetas), isFalse);
    });
  });

  test('la constancia se puede imprimir solo cuando ya se resolvió (aprobada o rechazada)',
      () async {
    final s = await _svc('almacen');
    expect(s.puedeImprimir(_solicitud(estado: EstadoSolicitud.pendiente)), isFalse);
    expect(s.puedeImprimir(_solicitud(estado: EstadoSolicitud.aprobada)), isTrue);
    expect(s.puedeImprimir(_solicitud(estado: EstadoSolicitud.rechazada)), isTrue);
  });

  group('crear', () {
    test('exige permiso, asunto y tipo válidos', () async {
      final repo = _Repo();
      final sinPermiso = await _svc('jefe_produccion', repo);
      expect(
          await sinPermiso.crear(const SolicitudNueva(tipo: TipoSolicitud.otro, asunto: 'Hola')),
          contains('permiso'));

      final s = await _svc('almacen', repo);
      expect(await s.crear(const SolicitudNueva(tipo: TipoSolicitud.otro, asunto: 'Hi')),
          contains('asunto'));
      expect(await s.crear(const SolicitudNueva(tipo: 'invalido', asunto: 'Asunto válido')),
          contains('tipo'));
      expect(repo.ultimaCreada, isNull);
    });

    test('rechaza cantidad en cero o negativa', () async {
      final repo = _Repo();
      final s = await _svc('almacen', repo);
      expect(
          await s.crear(const SolicitudNueva(
              tipo: TipoSolicitud.suministro, asunto: 'Falta azúcar', cantidadSugerida: 0)),
          contains('mayor a cero'));
    });

    test('crea con los datos ya limpios (trim) y traduce el error del servidor', () async {
      final repo = _Repo();
      final s = await _svc('control_calidad', repo);
      final error = await s.crear(const SolicitudNueva(
          tipo: TipoSolicitud.cambioReceta, asunto: '  Cambiar tartrazina  ',
          detalle: '  usar otro proveedor  '));
      expect(error, isNull);
      expect(repo.ultimaCreada!.asunto, 'Cambiar tartrazina');
      expect(repo.ultimaCreada!.detalle, 'usar otro proveedor');

      repo.negocio = const ErrorNegocioSolicitud('No tenés permiso para hacer solicitudes.');
      expect(
          await s.crear(const SolicitudNueva(tipo: TipoSolicitud.otro, asunto: 'Otra cosa')),
          'No tenés permiso para hacer solicitudes.');
    });
  });

  group('resolver', () {
    test('solo Gerencia resuelve, y solo si está pendiente', () async {
      final repo = _Repo();
      final almacen = await _svc('almacen', repo);
      expect(await almacen.aprobar(_solicitud()), contains('permiso'));

      final gerente = await _svc('gerente', repo);
      expect(await gerente.aprobar(_solicitud(estado: EstadoSolicitud.aprobada)),
          contains('ya fue resuelta'));
      expect(repo.resueltas, isEmpty);
    });

    test('rechazar exige motivo; aprobar no', () async {
      final repo = _Repo();
      final gerente = await _svc('gerente', repo);
      expect(await gerente.rechazar(_solicitud(), ''), contains('motivo'));
      expect(await gerente.rechazar(_solicitud(), 'No corresponde'), isNull);
      expect(await gerente.aprobar(_solicitud(id: 2)), isNull);
      expect(repo.resueltas, [1, 2]);
    });
  });
}
