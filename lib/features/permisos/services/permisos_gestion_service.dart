import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/permisos_modelos.dart';
import '../repositories/permisos_repository.dart';

/// Reglas de "Permisos por rol": solo Gerente ve y edita esta pantalla
/// (además del permiso del módulo 'permisos', por si alguna vez se lo
/// delega); el resto de la validación real — que no se pueda sacar a
/// Gerente el acceso a Usuarios/Permisos — la hace el servidor. No conoce
/// widgets.
class PermisosGestionService extends ChangeNotifier {
  PermisosGestionService(this._repo, this._usuario, {String? rolInicial})
      : rolSeleccionado = rolInicial ?? Rol.gerente;

  final PermisosRepository _repo;
  final Usuario _usuario;

  List<ModuloApp> modulos = [];
  String rolSeleccionado;
  Set<String> _permisosDelRol = {};

  bool cargando = true;
  String? error;

  /// Guarda qué casillas están mandando su cambio al servidor ("modulo:accion"),
  /// para no dejar tocar la misma dos veces mientras la primera todavía viaja.
  final Set<String> guardando = {};

  bool get puedeVer =>
      _usuario.rol == Rol.gerente && _usuario.puede(Modulo.permisos, Accion.ver, reglaAnterior: false);
  bool get puedeEditar =>
      _usuario.rol == Rol.gerente &&
      _usuario.puede(Modulo.permisos, Accion.editar, reglaAnterior: false);

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    notifyListeners();
    if (!puedeVer) {
      cargando = false;
      notifyListeners();
      return;
    }
    try {
      final r = await Future.wait([_repo.modulos(), _repo.permisosDeRol(rolSeleccionado)]);
      modulos = r[0] as List<ModuloApp>;
      _permisosDelRol = r[1] as Set<String>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Permisos. Revisá la conexión o que la migración v17 esté ejecutada.';
      if (kDebugMode) debugPrint('PermisosGestionService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> elegirRol(String rol) async {
    if (rol == rolSeleccionado) return;
    rolSeleccionado = rol;
    cargando = true;
    notifyListeners();
    try {
      _permisosDelRol = await _repo.permisosDeRol(rol);
      error = null;
    } catch (e) {
      error = 'No se pudo cargar los permisos de ese rol.';
      if (kDebugMode) debugPrint('PermisosGestionService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  bool tiene(String modulo, String accion) => _permisosDelRol.contains('$modulo:$accion');

  /// No deja sacarle a Gerente el acceso a Usuarios/Permisos desde acá
  /// tampoco — el servidor ya lo impide (trigger v17), pero avisar antes
  /// de mandar el pedido evita el viaje y el mensaje de error crudo.
  bool _esCandadoDeGerente(String modulo, String accion) =>
      rolSeleccionado == Rol.gerente &&
      (modulo == Modulo.usuarios || modulo == Modulo.permisos);

  /// Devuelve un mensaje de error, o null si salió bien.
  Future<String?> alternar(String modulo, String accion) async {
    if (!puedeEditar) return 'No tenés permiso para editar permisos.';
    final clave = '$modulo:$accion';
    if (guardando.contains(clave)) return null;
    final yaLoTiene = tiene(modulo, accion);
    if (yaLoTiene && _esCandadoDeGerente(modulo, accion)) {
      return 'No se le puede quitar a Gerente el acceso a Usuarios ni a Permisos.';
    }
    guardando.add(clave);
    // Optimista: se ve el cambio al toque; si el servidor lo rechaza, se
    // deshace y se muestra el motivo.
    if (yaLoTiene) {
      _permisosDelRol.remove(clave);
    } else {
      _permisosDelRol.add(clave);
    }
    notifyListeners();
    try {
      if (yaLoTiene) {
        await _repo.revocar(rolSeleccionado, modulo, accion);
      } else {
        await _repo.otorgar(rolSeleccionado, modulo, accion);
      }
      guardando.remove(clave);
      notifyListeners();
      return null;
    } catch (e) {
      // Deshacer el cambio optimista.
      if (yaLoTiene) {
        _permisosDelRol.add(clave);
      } else {
        _permisosDelRol.remove(clave);
      }
      guardando.remove(clave);
      notifyListeners();
      if (kDebugMode) debugPrint('PermisosGestionService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('row-level security') || t.contains('permission denied')) {
        return 'No tenés permiso para hacer esto.';
      }
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo guardar el cambio.';
    }
  }
}
