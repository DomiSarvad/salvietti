import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/presencia/models/presencia.dart';
import 'package:salvietti_control/features/presencia/repositories/presencia_repository.dart';
import 'package:salvietti_control/features/presencia/services/presencia_service.dart';

class _Repo implements PresenciaRepository {
  List<PresenciaUsuario> lista = [];
  final latidos = <int>[];
  bool sinRed = false;

  @override
  Future<void> latido(int pendientes) async {
    if (sinRed) throw Exception('sin red');
    latidos.add(pendientes);
  }

  @override
  Future<List<PresenciaUsuario>> recientes() async {
    if (sinRed) throw Exception('sin red');
    return lista;
  }
}

PresenciaUsuario _u(String id, String rol, {int segundos = 10, int pendientes = 0, bool activa = true}) =>
    PresenciaUsuario(
      usuarioId: id, rol: rol, nombre: 'Persona $id', ultimaSenal: DateTime(2026, 10, 15, 10, 32),
      pendientes: pendientes, activa: activa, segundosSinSenal: segundos,
    );

void main() {
  late _Repo repo;
  late DateTime ahora;
  var hayRed = true;
  var pendientes = 0;

  PresenciaService crear({String? yo = 'jarabes-1'}) => PresenciaService(
        repo,
        pendientes: () => pendientes,
        usuarioActual: () => yo,
        hayRed: () => hayRed,
        ahora: () => ahora,
      );

  setUp(() {
    repo = _Repo();
    ahora = DateTime(2026, 10, 15, 11);
    hayRed = true;
    pendientes = 0;
  });

  test('el latido manda cuántos registros quedan sin subir', () async {
    pendientes = 3;
    final s = crear();
    await s.latido();
    expect(repo.latidos, [3]);
  });

  test('sin sesión no manda latido', () async {
    final s = crear(yo: null);
    await s.latido();
    expect(repo.latidos, isEmpty);
  });

  test('avisa del área que dejó de dar señal (el ejemplo Soplado → Jarabes)', () async {
    repo.lista = [
      _u('soplado-1', 'soplado', segundos: 600), // 10 min sin señal
      _u('llenadora-1', 'llenadora', segundos: 600),
    ];
    final s = crear();
    await s.refrescar();

    final avisos = s.avisosDe(['soplado']);
    expect(avisos, hasLength(1));
    expect(avisos.single.tipo, TipoAvisoArea.sinSenal);
    expect(avisos.single.nombre, 'Persona soplado-1');
  });

  test('un corte de segundos no es alarma; si pasa el tiempo sin leer, sí', () async {
    repo.lista = [_u('soplado-1', 'soplado', segundos: 60)];
    final s = crear();
    await s.refrescar();
    expect(s.avisosDe(['soplado']), isEmpty);

    // Sin volver a leer, el tiempo sigue corriendo desde la última lectura.
    ahora = ahora.add(const Duration(minutes: 3));
    expect(s.avisosDe(['soplado']), hasLength(1));
  });

  test('conectado pero con registros por subir: avisa que los datos pueden cambiar', () async {
    repo.lista = [_u('soplado-1', 'soplado', pendientes: 4)];
    final s = crear();
    await s.refrescar();
    final a = s.avisosDe(['soplado']).single;
    expect(a.tipo, TipoAvisoArea.pendientes);
    expect(a.pendientes, 4);
  });

  test('no avisa de quien cerró sesión, ni de uno mismo', () async {
    repo.lista = [
      _u('soplado-1', 'soplado', segundos: 600, activa: false),
      _u('jarabes-1', 'jarabes', segundos: 600),
    ];
    final s = crear();
    await s.refrescar();
    expect(s.avisosDe(['soplado', 'jarabes']), isEmpty);
  });

  test('si ESTE dispositivo está sin red, no muestra avisos de otros (serían viejos)', () async {
    repo.lista = [_u('soplado-1', 'soplado', segundos: 600)];
    final s = crear();
    await s.refrescar();
    hayRed = false;
    expect(s.avisosDe(['soplado']), isEmpty);
  });
}
