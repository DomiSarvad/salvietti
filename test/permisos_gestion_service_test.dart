import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/core/constants.dart';
import 'package:salvietti_control/features/permisos/models/permisos_modelos.dart';
import 'package:salvietti_control/features/permisos/repositories/permisos_repository.dart';
import 'package:salvietti_control/features/permisos/services/permisos_gestion_service.dart';
import 'package:salvietti_control/models/usuario.dart';

class _RepoFalso implements PermisosRepository {
  Map<String, Set<String>> permisosPorRol;
  bool fallar = false;
  final otorgados = <String>[];
  final revocados = <String>[];

  _RepoFalso({Map<String, Set<String>>? permisosPorRol})
      : permisosPorRol = permisosPorRol ?? {};

  @override
  Future<List<ModuloApp>> modulos() async => const [
        ModuloApp(id: 'usuarios', nombre: 'Usuarios'),
        ModuloApp(id: 'permisos', nombre: 'Permisos por rol'),
        ModuloApp(id: 'mermas', nombre: 'Mermas'),
      ];

  @override
  Future<Set<String>> permisosDeRol(String rol) async =>
      Set.of(permisosPorRol[rol] ?? {});

  @override
  Future<void> otorgar(String rol, String modulo, String accion) async {
    if (fallar) throw Exception('sin conexión');
    otorgados.add('$rol/$modulo:$accion');
    permisosPorRol.putIfAbsent(rol, () => {}).add('$modulo:$accion');
  }

  @override
  Future<void> revocar(String rol, String modulo, String accion) async {
    if (fallar) throw Exception('sin conexión');
    revocados.add('$rol/$modulo:$accion');
    permisosPorRol[rol]?.remove('$modulo:$accion');
  }
}

Usuario _gerente({Set<String>? permisos}) => Usuario(
    id: 'u1', nombreCompleto: 'Jefa', rol: Rol.gerente, permisos: permisos);

void main() {
  test('solo Gerente puede ver la pantalla', () async {
    final noGerente =
        Usuario(id: 'u2', nombreCompleto: 'Op', rol: 'almacen', permisos: {'permisos:ver'});
    final s = PermisosGestionService(_RepoFalso(), noGerente);
    await s.iniciar();
    expect(s.puedeVer, isFalse);
    expect(s.modulos, isEmpty);
  });

  test('Gerente sin la fila permisos:ver tampoco entra (denegar por defecto)', () async {
    final s = PermisosGestionService(_RepoFalso(), _gerente(permisos: {}));
    await s.iniciar();
    expect(s.puedeVer, isFalse);
  });

  test('carga los módulos y los permisos del rol inicial (Gerente)', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'usuarios:ver', 'permisos:ver', 'permisos:editar'},
    });
    final s = PermisosGestionService(
        repo, _gerente(permisos: {'permisos:ver', 'permisos:editar'}));
    await s.iniciar();
    expect(s.modulos.map((m) => m.id), ['usuarios', 'permisos', 'mermas']);
    expect(s.tiene('usuarios', 'ver'), isTrue);
    expect(s.tiene('mermas', 'ver'), isFalse);
  });

  test('cambiar de rol recarga sus permisos', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'permisos:ver', 'permisos:editar'},
      'almacen': {'mermas:ver'},
    });
    final s = PermisosGestionService(
        repo, _gerente(permisos: {'permisos:ver', 'permisos:editar'}));
    await s.iniciar();
    await s.elegirRol('almacen');
    expect(s.rolSeleccionado, 'almacen');
    expect(s.tiene('mermas', 'ver'), isTrue);
  });

  test('alternar otorga y revoca, guardando en el repositorio', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'permisos:ver', 'permisos:editar'},
      'soplado': {},
    });
    final s = PermisosGestionService(
        repo, _gerente(permisos: {'permisos:ver', 'permisos:editar'}));
    await s.iniciar();
    await s.elegirRol('soplado');

    expect(await s.alternar('mermas', 'ver'), isNull);
    expect(s.tiene('mermas', 'ver'), isTrue);
    expect(repo.otorgados, ['soplado/mermas:ver']);

    expect(await s.alternar('mermas', 'ver'), isNull);
    expect(s.tiene('mermas', 'ver'), isFalse);
    expect(repo.revocados, ['soplado/mermas:ver']);
  });

  test('no deja sacarle a Gerente el acceso a Usuarios ni a Permisos', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'usuarios:ver', 'permisos:ver', 'permisos:editar'},
    });
    final s = PermisosGestionService(
        repo, _gerente(permisos: {'permisos:ver', 'permisos:editar'}));
    await s.iniciar();

    final error = await s.alternar('usuarios', 'ver');
    expect(error, contains('Gerente'));
    expect(s.tiene('usuarios', 'ver'), isTrue); // no se tocó
    expect(repo.revocados, isEmpty);
  });

  test('si el servidor rechaza el cambio, se deshace el optimismo y avisa', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'permisos:ver', 'permisos:editar'},
      'soplado': {},
    })..fallar = true;
    final s = PermisosGestionService(
        repo, _gerente(permisos: {'permisos:ver', 'permisos:editar'}));
    await s.iniciar();
    await s.elegirRol('soplado');

    final error = await s.alternar('mermas', 'ver');
    expect(error, isNotNull);
    expect(s.tiene('mermas', 'ver'), isFalse); // se deshizo
  });

  test('sin permiso de editar, alternar no hace nada', () async {
    final repo = _RepoFalso(permisosPorRol: {
      'gerente': {'permisos:ver'},
    });
    final s = PermisosGestionService(repo, _gerente(permisos: {'permisos:ver'}));
    await s.iniciar();
    expect(s.puedeEditar, isFalse);
    final error = await s.alternar('mermas', 'ver');
    expect(error, contains('permiso'));
    expect(repo.otorgados, isEmpty);
  });
}
