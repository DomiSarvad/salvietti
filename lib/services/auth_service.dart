import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../models/usuario.dart';
import 'supabase_service.dart';
import 'bitacora_service.dart';
import 'cliente_offline.dart';
import 'datos_empleado_service.dart';
import 'hive_service.dart';
import 'permisos_service.dart';
import 'sesion_inactividad.dart';
import 'sesion_offline.dart';

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
    final id = _usuarioActual?.id;
    if (id != null) unawaited(SesionOffline.marcarDatosCompletos(id).catchError((_) {}));
    notifyListeners();
  }

  /// Lo que dijo el servidor en el último ingreso con internet: si ya cargó
  /// sus datos personales (null = no se pudo consultar).
  bool? _datosCompletosServidor;

  /// Foto elegida sin conexión, todavía no subida a Supabase Storage.
  /// Mientras exista, la UI la muestra en vez de `usuario.avatarUrl`
  /// (que sigue apuntando a la foto vieja hasta que se sincronice).
  Uint8List? _fotoLocalPendiente;
  Uint8List? get fotoLocalPendiente => _fotoLocalPendiente;

  /// Entró SIN internet (con la huella guardada en esta compu, ver
  /// [SesionOffline]): no hay sesión de Supabase. Lo que registra queda en la
  /// cola a su nombre; cuando vuelve internet se reabre la sesión real sola
  /// ([_reconectar]) y la cola se sube.
  bool _sinConexion = false;
  bool get sinConexion => _sinConexion;

  /// Solo en memoria (nunca en disco), y solo mientras dura el ingreso sin
  /// internet: hace falta para abrir la sesión real cuando vuelva la conexión.
  String? _correoPendiente;
  String? _clavePendiente;
  Timer? _reintentoSesion;

  /// Mensaje para mostrar en el login (ej. por qué se cerró la sesión).
  String? avisoLogin;

  /// La fila de `usuarios` tal como vino del servidor, para guardarla junto
  /// con la huella (y poder armar el perfil sin internet).
  Map<String, dynamic>? _perfilCrudo;

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
    avisoLogin = null; // el aviso de por qué se cerró la sesión ya se vio

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
      unawaited(SesionInactividad.registrarActividad().catchError((_) {}));
      // Para poder entrar sin internet la próxima vez, en esta compu.
      final crudo = _perfilCrudo;
      if (crudo != null) {
        unawaited(SesionOffline.recordar(
          correo: correo,
          password: password,
          perfil: crudo,
          permisos: _usuarioActual?.permisos,
          datosCompletos: _datosCompletosServidor,
        ).catchError((_) {}));
      }
      // Las dos en segundo plano: no hace falta esperarlas para mostrar el
      // menú. Y si fallan no es un intento de contraseña fallido (antes un
      // error de la bitácora caía en el catch de abajo y se contaba como tal).
      unawaited(BitacoraService.registrarAccion(
        usuarioId: res.user!.id,
        accion: 'login',
      ).catchError((_) {}));
      // No es crítico: si falla, el próximo ingreso correcto lo limpia igual.
      unawaited(SupabaseService.client
          .rpc('intentos_login_registrar_exito', params: {'p_email': correo})
          .timeout(SupabaseService.timeoutRed)
          .then((_) {}, onError: (_) {}));
      return const ResultadoLogin(); // sin error
    } on Object catch (e) {
      final mensaje = _mensajeError(e);
      // Sin internet: se intenta con la huella guardada en esta compu. Un
      // problema de red no es un intento fallido de contraseña en el servidor.
      if (mensaje.startsWith('No se pudo conectar')) return _entrarSinConexion(correo, password);
      return await _registrarFallo(correo, mensaje);
    }
  }

  Future<ResultadoLogin> _entrarSinConexion(String correo, String password) async {
    try {
      final guardado = await SesionOffline.verificar(correo, password);
      final usuario = Usuario.fromMap(guardado.perfil).conPermisos(guardado.permisos);
      if (!usuario.activo) {
        return const ResultadoLogin(
            error: 'Tu cuenta está desactivada. Comunicate con el Gerente.');
      }
      _usuarioActual = usuario;
      // Primera vez sin haber cargado sus datos: se le piden igual (se guardan
      // en la compu y se suben con la cola cuando vuelva internet).
      _datosPendientes = guardado.datosCompletos == false;
      _sinConexion = true;
      _correoPendiente = correo;
      _clavePendiente = password;
      ClienteOffline.usuarioSinConexion = usuario.id;
      unawaited(SesionInactividad.registrarActividad().catchError((_) {}));
      _restaurarFotoPendienteLocal();
      _esperarConexion();
      notifyListeners();
      return const ResultadoLogin();
    } on ErrorSesionOffline catch (e) {
      return ResultadoLogin(error: e.mensaje);
    }
  }

  /// Mientras se trabaja sin internet: apenas vuelve la red (o cada 30 s, por
  /// si el wifi volvió sin que nadie avise) se abre la sesión real.
  void _esperarConexion() {
    ClienteOffline.hayRed.removeListener(_alVolverRed);
    ClienteOffline.hayRed.addListener(_alVolverRed);
    _reintentoSesion?.cancel();
    _reintentoSesion = Timer.periodic(const Duration(seconds: 30), (_) => _reconectar());
  }

  void _alVolverRed() {
    if (ClienteOffline.hayRed.value) _reconectar();
  }

  void _dejarDeEsperar() {
    ClienteOffline.hayRed.removeListener(_alVolverRed);
    _reintentoSesion?.cancel();
    _reintentoSesion = null;
    _correoPendiente = null;
    _clavePendiente = null;
    ClienteOffline.usuarioSinConexion = null;
  }

  bool _reconectando = false;

  Future<void> _reconectar() async {
    final correo = _correoPendiente, clave = _clavePendiente;
    if (!_sinConexion || _reconectando || correo == null || clave == null) return;
    _reconectando = true;
    try {
      final res = await SupabaseService.client.auth
          .signInWithPassword(email: correo, password: clave)
          .timeout(SupabaseService.timeoutRed);
      final id = res.user?.id;
      if (id == null) return;
      _sinConexion = false;
      _dejarDeEsperar();
      try {
        await _cargarPerfil(id);
      } catch (_) {
        // Se queda con el perfil guardado; se refresca en el próximo ingreso.
      }
      final crudo = _perfilCrudo;
      if (crudo != null) {
        unawaited(SesionOffline.recordar(
                correo: correo,
                password: clave,
                perfil: crudo,
                permisos: _usuarioActual?.permisos,
                datosCompletos: _datosCompletosServidor)
            .catchError((_) {}));
      }
      if (_usuarioActual != null && !_usuarioActual!.activo) {
        avisoLogin = 'Tu cuenta fue desactivada. Comunicate con el Gerente.';
        await cerrarSesion();
        return;
      }
      notifyListeners(); // la sincronización sube la cola sola en su próximo intento
    } on AuthException catch (e) {
      // La contraseña ya no es esa (la cambiaron con internet): hay que volver
      // a entrar. Lo registrado sin internet NO se pierde: queda en la cola y
      // se sube cuando esta persona vuelva a entrar con la contraseña nueva.
      if (e.message.contains('Invalid login credentials')) {
        avisoLogin = 'Tu contraseña cambió mientras estabas sin internet. Entrá con la nueva: '
            'lo que registraste sin conexión se sube después de entrar.';
        await cerrarSesion();
      }
    } catch (_) {
      // Sigue sin internet: se reintenta más tarde.
    } finally {
      _reconectando = false;
    }
  }

  Future<void> _cargarPerfil(String userId) async {
    final data = await SupabaseService.client
        .from('usuarios')
        .select()
        .eq('id', userId)
        .single();
    _perfilCrudo = Map<String, dynamic>.from(data);
    final perfil = Usuario.fromMap(data);
    // Permisos y datos personales a la vez (antes iban uno después del otro,
    // y el menú no aparecía hasta que terminaban los dos).
    // ¿Completó sus datos personales? Si no se puede consultar (sin conexión, o
    // la tabla todavía no existe) no se bloquea el ingreso.
    final datosFuturo = DatosEmpleadoService.obtener(userId)
        .then<bool?>((d) => d?.completo ?? false)
        .catchError((_) => null);
    final permisos = await PermisosService.delRol(perfil.rol);
    _usuarioActual = perfil.conPermisos(permisos);
    final completo = await datosFuturo;
    _datosCompletosServidor = completo;
    _datosPendientes = completo != null && _usuarioActual!.activo && !completo;
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
    if (user != null && SesionInactividad.vencida()) {
      // Se salió sin cerrar sesión y pasó demasiado tiempo: a ingresar de nuevo.
      avisoLogin = SesionInactividad.mensaje;
      try {
        await SupabaseService.client.auth.signOut();
      } catch (_) {
        // Sin internet puede fallar; da igual: la próxima vez que se abra la
        // app, la última actividad sigue vieja y se vuelve a cerrar acá.
      }
      notifyListeners();
      return;
    }
    if (user != null) {
      try {
        await _cargarPerfil(user.id);
      } catch (_) {
        // Sin internet y sin copia de esa consulta: se usa el perfil guardado
        // en el último ingreso con internet en esta compu (si lo hay).
        final guardado = SesionOffline.perfilDe(user.id);
        if (guardado == null) return; // muestra el login
        _usuarioActual = Usuario.fromMap(guardado.perfil).conPermisos(guardado.permisos);
        _datosPendientes = guardado.datosCompletos == false;
        _restaurarFotoPendienteLocal();
        notifyListeners();
      }
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

  /// La app estuvo sin usarse más de [SesionInactividad.limite]: se cierra la
  /// sesión con un aviso. Lo registrado sin internet sigue en la cola.
  Future<void> cerrarPorInactividad() async {
    avisoLogin = SesionInactividad.mensaje;
    await cerrarSesion();
  }

  Future<void> cerrarSesion() async {
    if (_usuarioActual != null) {
      try {
        await BitacoraService.registrarAccion(
          usuarioId: _usuarioActual!.id,
          accion: 'logout',
        );
      } catch (_) {
        // No impide cerrar la sesión.
      }
    }
    // Que las demás áreas no lo vean como "sin señal": cerró a propósito.
    try {
      await SupabaseService.client.rpc('presencia_salir').timeout(const Duration(seconds: 3));
    } catch (_) {
      // Sin internet o sin v42: no impide cerrar la sesión.
    }
    ClienteOffline.olvidarMemoria(); // catálogos en memoria del usuario que sale
    _sinConexion = false;
    _dejarDeEsperar();
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // Sin internet: la sesión se borra de esta compu igual.
    }
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
