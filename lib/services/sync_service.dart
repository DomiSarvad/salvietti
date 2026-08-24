import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

/// Orquesta la sincronización offline -> online.
///
/// Flujo (según los casos de uso):
///  1. Sin conexión: los movimientos se guardan en la cola local (Hive).
///  2. La UI muestra un indicador "N pendientes de sincronizar".
///  3. Al recuperar la conexión, se sincroniza automáticamente en orden
///     cronológico (FIFO); además el usuario puede forzar la subida con
///     el botón "Subir todo".
///  4. Cada movimiento lleva un `origen_offline_uuid` único: si por algún
///     motivo se reintenta un envío ya recibido, el índice único de la
///     base de datos evita duplicados (idempotencia).
class SyncService extends ChangeNotifier {
  bool _sincronizando = false;
  bool get sincronizando => _sincronizando;
  bool _online = true;
  bool get online => _online;

  StreamSubscription? _sub;

  void iniciarMonitoreo() {
    _sub = Connectivity().onConnectivityChanged.listen((results) async {
      final antesOffline = !_online;
      _online = !results.contains(ConnectivityResult.none);
      notifyListeners();
      if (_online && antesOffline) {
        await sincronizarTodo(); // auto-sync al recuperar conexión
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  int get pendientes => HiveService.cantidadPendientes;

  /// Sube toda la cola pendiente a Supabase. Se puede invocar manualmente
  /// (botón "Subir todo") o automáticamente al recuperar conexión.
  Future<String> sincronizarTodo() async {
    if (_sincronizando) return 'Ya hay una sincronización en curso.';
    _sincronizando = true;
    notifyListeners();

    final pendientes = HiveService.movimientosPendientes()
      ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn)); // FIFO

    int exitosos = 0;
    int fallidos = 0;

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

    _sincronizando = false;
    notifyListeners();
    return 'Sincronizados: $exitosos. Pendientes/fallidos: $fallidos.';
  }
}
