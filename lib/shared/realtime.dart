import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// Una suscripción activa (a Realtime u otra cosa) que se puede cancelar.
/// Los repositorios devuelven esto en vez de un `RealtimeChannel`, para que
/// los services se puedan probar con un repositorio falso.
abstract class Suscripcion {
  void cancelar();
}

/// Para repositorios falsos (tests) o cuando no hay nada que escuchar.
class SuscripcionNula implements Suscripcion {
  const SuscripcionNula();
  @override
  void cancelar() {}
}

/// Avisa (llamando a [onCambio]) cada vez que cambia una fila de cualquiera
/// de [tablas]. Solo para usar desde un repositorio. Las tablas tienen que
/// estar en la publicación `supabase_realtime` (v41/v42).
///
/// También avisa cuando el canal se vuelve a conectar después de un corte:
/// lo que cambió mientras no había conexión no llega por Realtime, así que
/// la pantalla tiene que recargar para no quedarse con datos viejos.
Suscripcion escucharTablas(String nombreCanal, List<String> tablas, void Function() onCambio) {
  final db = SupabaseService.client;
  final canal = db.channel(nombreCanal);
  for (final tabla in tablas) {
    canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tabla,
      callback: (_) => onCambio(),
    );
  }
  var conectadoAntes = false;
  canal.subscribe((estado, _) {
    if (estado != RealtimeSubscribeStatus.subscribed) return;
    if (conectadoAntes) onCambio(); // reconexión: puede haberse perdido algo
    conectadoAntes = true;
  });
  return _SuscripcionRealtime(canal);
}

class _SuscripcionRealtime implements Suscripcion {
  final RealtimeChannel _canal;
  const _SuscripcionRealtime(this._canal);
  @override
  void cancelar() => SupabaseService.client.removeChannel(_canal);
}
