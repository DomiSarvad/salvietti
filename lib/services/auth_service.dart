import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/usuario.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';
import 'hive_service.dart';

/// Cuenta intentos fallidos de login por correo, para el bloqueo temporal.
class _IntentoLogin {
  int fallos = 0;
  DateTime? bloqueadoHasta;
}

/// Regex de correo razonablemente estricta (evita símbolos inválidos,
/// espacios, o formatos claramente rotos) sin rechazar direcciones reales.
final RegExp _emailValido =
    RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$");

/// Maneja login/logout y expone el perfil (rol) del usuario autenticado.
/// Se registra en la bitácora de acciones cada inicio de sesión, tal como
/// piden los casos de uso ("saber qué usuario entra y qué hace").
class AuthService extends ChangeNotifier {
  static const _maxIntentos = 5;
  static const _bloqueoDuracion = Duration(seconds: 60);

  final Map<String, _IntentoLogin> _intentos = {};

  Usuario? _usuarioActual;
  Usuario? get usuarioActual => _usuarioActual;
  bool get autenticado => _usuarioActual != null;

  /// Foto elegida sin conexión, todavía no subida a Supabase Storage.
  /// Mientras exista, la UI la muestra en vez de `usuario.avatarUrl`
  /// (que sigue apuntando a la foto vieja hasta que se sincronice).
  Uint8List? _fotoLocalPendiente;
  Uint8List? get fotoLocalPendiente => _fotoLocalPendiente;

  /// Valida formato antes de tocar la red: largo excesivo, símbolos
  /// inválidos en el correo, contraseña vacía o con caracteres de control.
  String? _validarCredenciales(String email, String password) {
    if (email.isEmpty || password.isEmpty) {
      return 'Ingresa tu correo y tu contraseña.';
    }
    if (email.length > 254) return 'El correo es demasiado largo.';
    if (!_emailValido.hasMatch(email)) {
      return 'El correo no tiene un formato válido.';
    }
    if (password.length > Validacion.passwordMax) {
      return 'La contraseña es demasiado larga (máx. ${Validacion.passwordMax} caracteres).';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(password)) {
      return 'La contraseña contiene caracteres no permitidos.';
    }
    return null;
  }

  String _registrarFallo(_IntentoLogin intento, String mensaje) {
    intento.fallos++;
    if (intento.fallos >= _maxIntentos) {
      intento.bloqueadoHasta = DateTime.now().add(_bloqueoDuracion);
      return 'Demasiados intentos fallidos. Espera '
          '${_bloqueoDuracion.inSeconds} segundos e inténtalo de nuevo.';
    }
    final restantes = _maxIntentos - intento.fallos;
    return '$mensaje ($restantes intento${restantes == 1 ? '' : 's'} '
        'restante${restantes == 1 ? '' : 's'})';
  }

  Future<String?> iniciarSesion(String email, String password) async {
    final correo = email.trim().toLowerCase();

    final errorFormato = _validarCredenciales(correo, password);
    if (errorFormato != null) return errorFormato;

    final intento = _intentos.putIfAbsent(correo, () => _IntentoLogin());
    if (intento.bloqueadoHasta != null) {
      final restante = intento.bloqueadoHasta!.difference(DateTime.now());
      if (restante > Duration.zero) {
        return 'Demasiados intentos fallidos. Espera '
            '${restante.inSeconds} segundos e inténtalo de nuevo.';
      }
      intento.bloqueadoHasta = null;
      intento.fallos = 0;
    }

    try {
      final res = await SupabaseService.client.auth
          .signInWithPassword(email: correo, password: password)
          .timeout(SupabaseService.timeoutRed);
      if (res.user == null) {
        return _registrarFallo(intento, 'No se pudo iniciar sesión.');
      }
      await _cargarPerfil(res.user!.id);
      await BitacoraService.registrarAccion(
        usuarioId: res.user!.id,
        accion: 'login',
      );
      _intentos.remove(correo);
      return null; // sin error
    } on Object catch (e) {
      return _registrarFallo(intento, _mensajeError(e));
    }
  }

  Future<void> _cargarPerfil(String userId) async {
    final data = await SupabaseService.client
        .from('usuarios')
        .select()
        .eq('id', userId)
        .single();
    _usuarioActual = Usuario.fromMap(data);
    _restaurarFotoPendienteLocal();
    notifyListeners();
  }

  /// Si quedó una foto sin subir de una sesión anterior (se cerró la app
  /// antes de reconectar), se vuelve a mostrar localmente al reabrir.
  void _restaurarFotoPendienteLocal() {
    final pendiente = HiveService.fotoPendiente();
    if (pendiente != null && pendiente['usuarioId'] == _usuarioActual?.id) {
      _fotoLocalPendiente = pendiente['bytes'] as Uint8List;
    }
  }

  Future<void> recuperarSesion() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      await _cargarPerfil(user.id);
    }
  }

  /// Paso 1 de "¿Olvidaste tu contraseña?": envía un código de un solo uso
  /// al correo. Se usa un código en vez de un link porque la app corre en
  /// escritorio/móvil/web sin un dominio propio que pueda capturar el
  /// redirect del link — el código funciona igual en cualquier plataforma.
  Future<String?> solicitarRecuperacion(String email) async {
    final correo = email.trim().toLowerCase();
    if (correo.isEmpty) return 'Ingresa tu correo.';
    if (correo.length > 254) return 'El correo es demasiado largo.';
    if (!_emailValido.hasMatch(correo)) {
      return 'El correo no tiene un formato válido.';
    }
    try {
      await SupabaseService.client.auth
          .resetPasswordForEmail(correo)
          .timeout(SupabaseService.timeoutRed);
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  /// Paso 2: valida el código recibido y establece la nueva contraseña.
  /// Al terminar cierra la sesión temporal que abre `verifyOTP`, para que
  /// el usuario entre de nuevo por el formulario normal con su clave nueva.
  Future<String?> confirmarRecuperacion({
    required String email,
    required String codigo,
    required String nuevaPassword,
  }) async {
    final correo = email.trim().toLowerCase();
    final token = codigo.trim();
    if (token.isEmpty) return 'Ingresa el código que recibiste por correo.';
    if (nuevaPassword.length < Validacion.passwordMin) {
      return 'La contraseña debe tener al menos ${Validacion.passwordMin} caracteres.';
    }
    if (nuevaPassword.length > Validacion.passwordMax) {
      return 'La contraseña es demasiado larga (máx. ${Validacion.passwordMax} caracteres).';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(nuevaPassword)) {
      return 'La contraseña contiene caracteres no permitidos.';
    }
    try {
      await SupabaseService.client.auth
          .verifyOTP(email: correo, token: token, type: OtpType.recovery)
          .timeout(SupabaseService.timeoutRed);
      await SupabaseService.client.auth
          .updateUser(UserAttributes(password: nuevaPassword))
          .timeout(SupabaseService.timeoutRed);
      await SupabaseService.client.auth.signOut();
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  /// Actualiza el nombre visible y/o la foto del usuario que tiene la
  /// sesión abierta. Disponible para cualquier rol: cada quien administra
  /// su propio perfil (el rol y el estado activo quedan protegidos por el
  /// trigger del servidor, sin importar lo que se envíe acá).
  Future<String?> actualizarPerfil({String? nombreCompleto, String? avatarUrl}) async {
    if (_usuarioActual == null) return 'No hay sesión activa.';
    final nombre = nombreCompleto?.trim();
    if (nombre != null) {
      if (nombre.isEmpty) return 'El nombre completo es obligatorio.';
      if (nombre.length > 120) return 'El nombre completo es demasiado largo.';
    }
    try {
      final cambios = <String, dynamic>{
        if (nombre != null) 'nombre_completo': nombre,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };
      if (cambios.isEmpty) return null;
      await SupabaseService.client
          .from('usuarios')
          .update(cambios)
          .eq('id', _usuarioActual!.id)
          .timeout(SupabaseService.timeoutRed);
      _usuarioActual = Usuario(
        id: _usuarioActual!.id,
        nombreCompleto: nombre ?? _usuarioActual!.nombreCompleto,
        rol: _usuarioActual!.rol,
        area: _usuarioActual!.area,
        activo: _usuarioActual!.activo,
        avatarUrl: avatarUrl ?? _usuarioActual!.avatarUrl,
      );
      notifyListeners();
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  /// Guarda una foto elegida sin conexión: se muestra de inmediato desde
  /// el dispositivo y queda en cola para subirse a Supabase Storage en
  /// cuanto vuelva la conexión (ver `sincronizarFotoPendiente`).
  Future<String?> guardarFotoOffline(Uint8List bytes, String ext) async {
    if (_usuarioActual == null) return 'No hay sesión activa.';
    await HiveService.guardarFotoPendiente(_usuarioActual!.id, bytes, ext);
    _fotoLocalPendiente = bytes;
    notifyListeners();
    return null;
  }

  /// La llama `SyncService` al recuperar conexión (o el botón "Subir
  /// todo"). Si falla, la foto simplemente sigue pendiente para el
  /// próximo intento — nunca se pierde ni se borra sin haberse subido.
  Future<void> sincronizarFotoPendiente() async {
    final pendiente = HiveService.fotoPendiente();
    if (pendiente == null) return;
    if (_usuarioActual == null || pendiente['usuarioId'] != _usuarioActual!.id) {
      return;
    }
    try {
      final bytes = pendiente['bytes'] as Uint8List;
      final ext = pendiente['ext'] as String;
      final ruta = '${_usuarioActual!.id}/avatar.$ext';
      await SupabaseService.client.storage.from('avatars').uploadBinary(
            ruta,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final urlPublica =
          SupabaseService.client.storage.from('avatars').getPublicUrl(ruta);
      final url = '$urlPublica?t=${DateTime.now().millisecondsSinceEpoch}';
      await actualizarPerfil(avatarUrl: url);
      await HiveService.limpiarFotoPendiente();
      _fotoLocalPendiente = null;
      notifyListeners();
    } catch (_) {
      // Sigue en la cola: se reintenta en la próxima sincronización.
    }
  }

  /// Cambia la contraseña del usuario autenticado (requiere conexión: es
  /// una operación de Supabase Auth, no forma parte de la cola offline).
  Future<String?> cambiarPassword(String nuevaPassword) async {
    if (nuevaPassword.length < Validacion.passwordMin) {
      return 'La contraseña debe tener al menos ${Validacion.passwordMin} caracteres.';
    }
    if (nuevaPassword.length > Validacion.passwordMax) {
      return 'La contraseña es demasiado larga (máx. ${Validacion.passwordMax} caracteres).';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(nuevaPassword)) {
      return 'La contraseña contiene caracteres no permitidos.';
    }
    try {
      await SupabaseService.client.auth
          .updateUser(UserAttributes(password: nuevaPassword))
          .timeout(SupabaseService.timeoutRed);
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
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

  /// Alta de un nuevo usuario — solo la puede invocar el Gerente (reforzado
  /// también por RLS y por la propia función del servidor). Se crea vía la
  /// función `crear_usuario_admin` (RPC) en vez de `auth.signUp()`: signUp
  /// reemplazaría la sesión activa por la del usuario nuevo y, si el
  /// proyecto exige confirmar el correo, esa persona nunca podría entrar.
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
    final correo = email.trim().toLowerCase();
    final nombre = nombreCompleto.trim();

    final errorFormato = _validarCredenciales(correo, password);
    if (errorFormato != null) return errorFormato;
    if (nombre.isEmpty) return 'El nombre completo es obligatorio.';
    if (nombre.length > 120) return 'El nombre completo es demasiado largo.';
    if (password.length < Validacion.passwordMin) {
      return 'La contraseña debe tener al menos ${Validacion.passwordMin} caracteres.';
    }
    if (!Rol.todos.contains(rol)) return 'Rol inválido.';

    try {
      await SupabaseService.client.rpc('crear_usuario_admin', params: {
        'p_email': correo,
        'p_password': password,
        'p_nombre_completo': nombre,
        'p_rol': rol,
        'p_area': area,
      }).timeout(SupabaseService.timeoutRed);
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  String _mensajeError(Object e) {
    if (e is PostgrestException) return e.message;
    final s = e.toString();
    if (s.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    return 'Error: $s';
  }
}
