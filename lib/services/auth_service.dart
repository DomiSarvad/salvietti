import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/usuario.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';
import 'datos_empleado_service.dart';
import 'hive_service.dart';
import 'permisos_service.dart';

/// Resultado de un intento de inicio de sesión. Si [segundosEspera] no es
/// null, hay un bloqueo temporal en curso: la pantalla arma su propia
/// cuenta regresiva con ese número (el servidor no la "empuja" segundo a
/// segundo, solo informa cuánto falta en el momento de esta respuesta).
class ResultadoLogin {
  final String? error;
  final int? segundosEspera;
  const ResultadoLogin({this.error, this.segundosEspera});
  bool get ok => error == null && segundosEspera == null;
}

/// Regex de correo razonablemente estricta (evita símbolos inválidos,
/// espacios, o formatos claramente rotos) sin rechazar direcciones reales.
final RegExp _emailValido =
    RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$");

/// Maneja login/logout y expone el perfil (rol) del usuario autenticado.
/// Se registra en la bitácora de acciones cada inicio de sesión, tal como
/// piden los casos de uso ("saber qué usuario entra y qué hace").
class AuthService extends ChangeNotifier {
  Usuario? _usuarioActual;
  Usuario? get usuarioActual => _usuarioActual;
  bool get autenticado => _usuarioActual != null;

  /// El empleado todavía no completó sus datos personales obligatorios: la app
  /// le muestra "Completá tus datos" y no lo deja pasar hasta guardarlos.
  bool _datosPendientes = false;
  bool get datosPendientes => _datosPendientes;

  /// Se llama al guardar los datos obligatorios.
  void datosCompletados() {
    _datosPendientes = false;
    notifyListeners();
  }

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

  /// Bloqueo escalonado por intentos fallidos: lo lleva el servidor (tabla
  /// `intentos_login`, función v23), por correo — así resiste cerrar la app
  /// y protege igual si prueban desde otro dispositivo. 5 fallos bloquean
  /// 30s, 10 fallos 2min, 15 fallos 10min, 20 fallos 30min, 25 fallos
  /// bloquean la cuenta hasta que el Gerente la desbloquee.
  Future<Map<String, dynamic>?> _estadoBloqueo(String correo) async {
    try {
      final r = await SupabaseService.client
          .rpc('intentos_login_estado', params: {'p_email': correo})
          .timeout(SupabaseService.timeoutRed);
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      // Sin la migración v23 o sin conexión: no se bloquea el ingreso por
      // esto, el error real (si lo hay) lo va a dar signInWithPassword.
      return null;
    }
  }

  ResultadoLogin _resultadoBloqueo(Map<String, dynamic> estado) {
    if (estado['permanente'] == true) {
      return const ResultadoLogin(
          error: 'Esta cuenta quedó bloqueada por demasiados intentos fallidos. '
              'Solo el Gerente puede desbloquearla.');
    }
    return ResultadoLogin(segundosEspera: (estado['espera_segundos'] as num?)?.toInt() ?? 60);
  }

  /// Registra el fallo en el servidor y arma el resultado: bloqueo si
  /// corresponde, o el mensaje simple con los intentos que quedan.
  Future<ResultadoLogin> _registrarFallo(String correo, String mensaje) async {
    try {
      final r = await SupabaseService.client
          .rpc('intentos_login_registrar_fallo', params: {'p_email': correo})
          .timeout(SupabaseService.timeoutRed);
      final estado = Map<String, dynamic>.from(r as Map);
      if (estado['permitido'] == false) return _resultadoBloqueo(estado);
      final restantes = (estado['intentos_restantes'] as num?)?.toInt();
      if (restantes == null) return ResultadoLogin(error: mensaje);
      return ResultadoLogin(
          error: '$mensaje ($restantes intento${restantes == 1 ? '' : 's'} '
              'restante${restantes == 1 ? '' : 's'})');
    } catch (_) {
      return ResultadoLogin(error: mensaje); // sin v23 o sin conexión: mensaje simple
    }
  }

  Future<ResultadoLogin> iniciarSesion(String email, String password) async {
    final correo = email.trim().toLowerCase();

    final errorFormato = _validarCredenciales(correo, password);
    if (errorFormato != null) return ResultadoLogin(error: errorFormato);

    final estadoPrevio = await _estadoBloqueo(correo);
    if (estadoPrevio != null && estadoPrevio['permitido'] == false) {
      return _resultadoBloqueo(estadoPrevio);
    }

    try {
      final res = await SupabaseService.client.auth
          .signInWithPassword(email: correo, password: password)
          .timeout(SupabaseService.timeoutRed);
      if (res.user == null) {
        return await _registrarFallo(correo, 'No se pudo iniciar sesión.');
      }
      await _cargarPerfil(res.user!.id);
      if (_usuarioActual != null && !_usuarioActual!.activo) {
        await SupabaseService.client.auth.signOut();
        _usuarioActual = null;
        notifyListeners();
        return const ResultadoLogin(
            error: 'Tu cuenta está desactivada. Comunicate con el Gerente.');
      }
      await BitacoraService.registrarAccion(
        usuarioId: res.user!.id,
        accion: 'login',
      );
      try {
        await SupabaseService.client
            .rpc('intentos_login_registrar_exito', params: {'p_email': correo})
            .timeout(SupabaseService.timeoutRed);
      } catch (_) {
        // No es crítico: si falla, el próximo ingreso correcto lo limpia igual.
      }
      return const ResultadoLogin(); // sin error
    } on Object catch (e) {
      final mensaje = _mensajeError(e);
      // Un problema de red no es un intento fallido de contraseña.
      if (mensaje.startsWith('No se pudo conectar')) return ResultadoLogin(error: mensaje);
      return await _registrarFallo(correo, mensaje);
    }
  }

  Future<void> _cargarPerfil(String userId) async {
    final data = await SupabaseService.client
        .from('usuarios')
        .select()
        .eq('id', userId)
        .single();
    final perfil = Usuario.fromMap(data);
    _usuarioActual = perfil.conPermisos(await PermisosService.delRol(perfil.rol));
    // ¿Completó sus datos personales? Si no se puede consultar (sin conexión, o
    // la tabla todavía no existe) no se bloquea el ingreso.
    try {
      final datos = await DatosEmpleadoService.obtener(userId);
      _datosPendientes = _usuarioActual!.activo && !(datos?.completo ?? false);
    } catch (_) {
      _datosPendientes = false;
    }
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
      if (_usuarioActual != null && !_usuarioActual!.activo) {
        await SupabaseService.client.auth.signOut();
        _usuarioActual = null;
        notifyListeners();
      }
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
      // Si verifyOTP ya abrió la sesión de recuperación y lo que falló fue
      // el cambio de contraseña (red, validación del servidor), esa sesión
      // temporal queda activa igual — sin cerrarla, reabrir la app antes de
      // reintentar dejaría entrar sin haber cambiado nada.
      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {
        // Sin sesión que cerrar (verifyOTP nunca llegó a abrir una) u otro
        // error de red acá: no tapa el mensaje real de abajo.
      }
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
        permisos: _usuarioActual!.permisos,
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
    // Que las demás áreas no lo vean como "sin señal": cerró a propósito.
    try {
      await SupabaseService.client.rpc('presencia_salir').timeout(const Duration(seconds: 3));
    } catch (_) {
      // Sin internet o sin v42: no impide cerrar la sesión.
    }
    await SupabaseService.client.auth.signOut();
    _usuarioActual = null;
    _datosPendientes = false;
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

  /// Edición de un usuario por el Gerente (nombre, correo, rol, área y estado).
  /// El cambio de correo se hace en el servidor (función
  /// `editar_usuario_admin`), porque el correo vive en la cuenta de acceso.
  Future<String?> editarUsuario({
    required String id,
    required String email,
    required String nombreCompleto,
    required String rol,
    String? area,
    required bool activo,
  }) async {
    if (_usuarioActual == null || !_usuarioActual!.puedeCrearUsuarios) {
      return 'No tiene permisos para editar usuarios.';
    }
    final correo = email.trim().toLowerCase();
    final nombre = nombreCompleto.trim();
    if (nombre.isEmpty) return 'El nombre completo es obligatorio.';
    if (nombre.length > 120) return 'El nombre completo es demasiado largo.';
    if (correo.isEmpty) return 'Ingresá el correo.';
    if (!Rol.todos.contains(rol)) return 'Rol inválido.';
    try {
      await SupabaseService.client.rpc('editar_usuario_admin', params: {
        'p_id': id,
        'p_email': correo,
        'p_nombre_completo': nombre,
        'p_rol': rol,
        'p_area': area,
        'p_activo': activo,
      }).timeout(SupabaseService.timeoutRed);
      // Si el Gerente se edita a sí mismo, se refresca su propio perfil.
      if (id == _usuarioActual!.id) {
        await _cargarPerfil(id);
      }
      return null;
    } on Object catch (e) {
      return _mensajeError(e);
    }
  }

  String _mensajeError(Object e) {
    if (e is PostgrestException) {
      if (e.code == 'PGRST202' || e.message.contains('Could not find the function')) {
        return 'Falta ejecutar schema_v14_roles_y_edicion_usuarios.sql en Supabase.';
      }
      return e.message;
    }
    final s = e.toString();
    if (s.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    // Falla de red real (sin internet, DNS, servidor inalcanzable) — no
    // es un error de credenciales, así que no tiene sentido mostrar la
    // excepción técnica cruda ("Failed to fetch", etc.).
    if (e is AuthRetryableFetchException ||
        e is TimeoutException ||
        s.contains('Failed to fetch') ||
        s.contains('SocketException') ||
        s.contains('ClientException')) {
      return 'No se pudo conectar. Revisa tu conexión a internet e '
          'intenta de nuevo.';
    }
    return 'Error: $s';
  }
}
