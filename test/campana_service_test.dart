import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/notificaciones/models/aviso_campana.dart';
import 'package:salvietti_control/features/notificaciones/repositories/campana_repository.dart';
import 'package:salvietti_control/features/notificaciones/services/campana_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _Repo implements CampanaRepository {
  int compras = 0, solicitudes = 0, recetasGerente = 0;
  List<RespuestaPropia> respuestas = [];
  final _vistos = <String>{};

  @override
  Future<int> comprasPendientes() async => compras;
  @override
  Future<int> solicitudesPendientes() async => solicitudes;
  @override
  Future<int> recetasEsperando({required String falta}) async => falta == 'gerente' ? recetasGerente : 0;
  @override
  Future<List<RespuestaPropia>> respuestasPropias(String usuarioId, DateTime desde) async => respuestas;
  @override
  Set<String> vistos(String usuarioId) => _vistos;
  @override
  Future<void> marcarVistos(String usuarioId, Iterable<String> claves) async => _vistos.addAll(claves);
  @override
  Suscripcion escucharCambios(void Function() onCambio) => const SuscripcionNula();
}

final _gerente = Usuario(id: 'g', nombreCompleto: 'G', rol: 'gerente', permisos: {
  'compras:aprobar', 'aprobaciones:aprobar', 'recetas:aprobar', 'solicitudes:ver',
});
final _almacen = Usuario(id: 'a', nombreCompleto: 'A', rol: 'almacen', permisos: {
  'compras:ver', 'compras:crear', 'solicitudes:ver', 'solicitudes:crear',
});

void main() {
  test('el Gerente ve pedidos de compra, solicitudes y recetas por confirmar', () async {
    final repo = _Repo()
      ..compras = 2
      ..solicitudes = 1
      ..recetasGerente = 1;
    final s = CampanaService(repo, _gerente);
    await s.cargar();
    expect(s.avisos.map((a) => a.ruta), ['compras', 'solicitudes', 'jarabes']);
    expect(s.total, 4);
  });

  test('Almacén no ve lo que no le toca aprobar, aunque haya', () async {
    final repo = _Repo()
      ..compras = 5
      ..solicitudes = 3;
    final s = CampanaService(repo, _almacen);
    await s.cargar();
    expect(s.avisos, isEmpty);
    expect(s.puedeCrearSolicitud, isTrue);
  });

  test('las respuestas propias cuentan hasta que se abren', () async {
    final repo = _Repo()
      ..respuestas = const [
        RespuestaPropia('compra:1', 'compra'),
        RespuestaPropia('compra:2', 'compra'),
        RespuestaPropia('solicitud:9', 'solicitud'),
      ];
    final s = CampanaService(repo, _almacen);
    await s.cargar();
    expect(s.total, 3);
    await s.abrir(s.avisos.firstWhere((a) => a.id == 'respuestas_compras'));
    expect(s.total, 1); // queda solo la de la solicitud
    expect(s.avisos.single.id, 'respuestas_solicitudes');
  });

  test('sin nada pendiente, la campana queda en cero', () async {
    final s = CampanaService(_Repo(), _gerente);
    await s.cargar();
    expect(s.total, 0);
  });
}
