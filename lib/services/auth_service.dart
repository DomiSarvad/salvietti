import 'package:flutter/foundation.dart';
import '../models/usuario.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';

/// Maneja login/logout y expone el perfil (rol) del usuario autenticado.
/// Se registra en la bitácora de acciones cada inicio de sesión, tal como
/// piden los casos de uso ("saber qué usuario entra y qué hace").
class AuthService extends ChangeNotifier {
  Usuario? _usuarioActual;
  Usuario? get usuarioActual => _usuarioActual;
  bool get autenticado => _usuarioActual != null;

  Future<String?> iniciarSesion(String email, String password) async {
    try {
      final res = await SupabaseService.client.auth
          .signInWithPassword(email: email, password: password);
      if (res.user == null) return 'No se pudo iniciar sesión.';
      await _cargarPerfil(res.user!.id);
      await BitacoraService.registrarAccion(
        usuarioId: res.user!.id,
        accion: 'login',
      );
      return null; // sin error
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  Future<void> _cargarPerfil(String userId) async {
    final data = await SupabaseService.client
        .from('usuarios')
        .select()
        .eq('id', userId)
        .single();
    _usuarioActual = Usuario.fromMap(data);
    notifyListeners();
  }

  Future<void> recuperarSesion() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      await _cargarPerfil(user.id);
    }
  }

  Future<void> cerrarSesion() async {
    if (_usuarioActual != null) {
      await BitacoraService.registrarAccion(
        usuarioId: _usuarioActual!.id,
        accion: 'logout',
      );
    }
    await SupabaseService.client.auth.signOut();
    _usuarioActual = null;
    notifyListeners();
  }

  /// Alta de un nuevo usuario — solo la puede invocar Almacén o Gerente
  /// (reforzado también por RLS en el servidor).
  Future<String?> crearUsuario({
    required String email,
    required String password,
    required String nombreCompleto,
    required String rol,
    String? area,
  }) async {
    if (_usuarioActual == null || !_usuarioActual!.puedeCrearUsuarios) {
      return 'No tiene permisos para crear usuarios.';
    }
    try {
      final res = await SupabaseService.client.auth.signUp(
        email: email,
        password: password,
      );
      if (res.user == null) return 'No se pudo crear la cuenta.';
      await SupabaseService.client.from('usuarios').insert({
        'id': res.user!.id,
        'nombre_completo': nombreCompleto,
        'rol': rol,
        'area': area,
        'creado_por': _usuarioActual!.id,
      });
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    return 'Error: $s';
  }
}
