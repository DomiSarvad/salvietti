import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'cliente_offline.dart';
import 'cola_offline.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

/// Resumen de una sincronización que subió o rechazó algo (para avisar).
class ResultadoSync {
  final int subidas;
  final int rechazadas;
  const ResultadoSync(this.subidas, this.rechazadas);
}

/// Orquesta la sincronización offline -> online.
///
/// Flujo (según los casos de uso):
///  1. Sin conexión: lo que se registra se guarda en la compu (Hive). Para
///     los módulos nuevos lo hace `ClienteOffline` (cualquier escritura a
///     Supabase); los movimientos legacy siguen con su cola propia.
///  2. La UI muestra un indicador "N pendientes de sincronizar".
///  3. Al recuperar la conexión, se sincroniza automáticamente en orden
///     cronológico (FIFO); además el usuario puede forzar la subida con
///     el botón "Sincronizar ahora" (Configuración). Mientras quede algo
///     pendiente se reintenta cada 30 s, porque con wifi sin salida a
///     internet connectivity_plus no avisa cuando vuelve la conexión.
///  4. Cada movimiento legacy lleva un `origen_offline_uuid` único: si por
///     algún motivo se reintenta un envío ya recibido, el índice único de la
///     base de datos evita duplicados (idempotencia).
class SyncService extends ChangeNotifier {
  bool _sincronizando = false;
  bool get sincronizando => _sincronizando;

  bool _hayInterfaz = true;
  bool get online => _hayInterfaz && ClienteOffline.hayRed.value;

  StreamSubscription? _sub;
  Timer? _reintento;
  AuthService? _authService;

  final _resultados = StreamController<ResultadoSync>.broadcast();

  /// Cada sincronización que subió o rechazó algo.
  Stream<ResultadoSync> get resultados => _resultados.stream;

  /// Se llama desde el `ChangeNotifierProxyProvider` en main.dart para que
  /// esta clase pueda pedirle a AuthService que suba la foto de perfil
  /// pendiente al sincronizar (sin que SyncService dependa de construir
  /// su propia instancia de AuthService).
  void vincularAuth(AuthService auth) => _authService = auth;

  void iniciarMonitoreo() {
    Connectivity().checkConnectivity().then(_alCambiarInterfaz);
    _sub = Connectivity().onConnectivityChanged.listen(_alCambiarInterfaz);
    ClienteOffline.hayRed.addListener(_alCambiarRed);
    ColaOffline.cambios.addListener(notifyListeners);
    _reintento = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_haySubibles && !_sincronizando) sincronizarTodo();
    });
    // Lo que quedó de una sesión anterior (se cerró la app sin internet).
    if (_haySubibles) Future.delayed(const Duration(seconds: 3), sincronizarTodo);
  }

  void _alCambiarInterfaz(List<ConnectivityResult> results) {
    final antesOffline = !online;
    _hayInterfaz = !results.contains(ConnectivityResult.none);
    ClienteOffline.sinInterfaz = !_hayInterfaz;
    notifyListeners();
    if (online && antesOffline) sincronizarTodo(); // auto-sync al recuperar conexión
  }

  void _alCambiarRed() {
    notifyListeners();
    if (online && _haySubibles && !_sincronizando) sincronizarTodo();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reintento?.cancel();
    ClienteOffline.hayRed.removeListener(_alCambiarRed);
    ColaOffline.cambios.removeListener(notifyListeners);
    _resultados.close();
    super.dispose();
  }

  bool get _haySubibles =>
      HiveService.cantidadPendientes > 0 ||
      HiveService.hayFotoPendiente ||
      ColaOffline.cantidadPendientes > 0;

  int get pendientes =>
      HiveService.cantidadPendientes +
      (HiveService.hayFotoPendiente ? 1 : 0) +
      ColaOffline.cantidadPendientes;

  /// Operaciones que el servidor rechazó al subirlas (ver Configuración).
  int get conError => ColaOffline.cantidadConError;

  List<OperacionOffline> get operacionesPendientes => ColaOffline.pendientes();
  List<OperacionOffline> get operacionesConError => ColaOffline.conError();

  /// Las que hizo otra persona en esta compu: se suben cuando esa persona
  /// vuelva a iniciar sesión acá (se registran a su nombre, no al de quien
  /// esté usando la app ahora).
  bool esDeOtroUsuario(OperacionOffline op) =>
      op.usuario != SupabaseService.currentUser?.id;

  Future<void> reintentar(OperacionOffline op) async {
    await ColaOffline.reintentar(op);
    if (online) await sincronizarTodo();
  }

  Future<void> descartar(OperacionOffline op) => ColaOffline.descartar(op);

  /// Sube toda la cola pendiente a Supabase. Se puede invocar manualmente
  /// (botón "Sincronizar ahora") o automáticamente al recuperar conexión.
  Future<String> sincronizarTodo() async {
    if (_sincronizando) return 'Ya hay una sincronización en curso.';
    _sincronizando = true;
    notifyListeners();

    int exitosos = 0;
    int fallidos = 0;
    int rechazados = 0;
    try {
      final pendientes = HiveService.movimientosPendientes()
        ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn)); // FIFO

      for (final mov in pendientes) {
        try {
          await SupabaseService.client
              .from('movimientos')
              .insert(mov.toSupabaseMap());
          await HiveService.quitarDeCola(mov.offlineUuid);
          exitosos++;
        } catch (_) {
          fallidos++; // se queda en la cola para el próximo intento
        }
      }

      await _authService?.sincronizarFotoPendiente();

      final r = await _subirColaNueva();
      if (r != null) {
        exitosos += r.subidas;
        rechazados += r.rechazadas;
        if (r.subidas + r.rechazadas > 0) _resultados.add(ResultadoSync(r.subidas, r.rechazadas));
      }
    } finally {
      _sincronizando = false;
      notifyListeners();
    }
    final quedan = pendientes;
    return 'Sincronizados: $exitosos.'
        '${rechazados > 0 ? ' Rechazados por el servidor: $rechazados (ver la lista).' : ''}'
        '${quedan > 0 || fallidos > 0 ? ' Pendientes: $quedan.' : ''}';
  }

  Future<ResultadoSubida?> _subirColaNueva() async {
    final auth = SupabaseService.client.auth;
    final sesion = auth.currentSession;
    if (sesion == null || !ColaOffline.hayPendientesDe(sesion.user.id)) return null;
    Future<void> refrescar() async {
      try {
        await auth.refreshSession();
      } catch (_) {
        // Sin red todavía: subirCola lo trata como "reintentar después".
      }
    }

    if (sesion.isExpired) await refrescar();
    try {
      return await ClienteOffline.subirCola(
        usuario: sesion.user.id,
        token: () => auth.currentSession?.accessToken,
        refrescarToken: refrescar,
      );
    } catch (_) {
      return null; // error inesperado: queda todo en la cola para el próximo intento
    }
  }
}
