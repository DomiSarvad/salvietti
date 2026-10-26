import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import '../core/constants.dart';
import '../services/cliente_offline.dart';
import '../services/cola_offline.dart' show OperacionOffline;
import '../services/sync_service.dart';

/// Avisos globales del modo sin conexión, para cualquier pantalla:
///  - "Sin internet: se guardó en esta compu" cada vez que una escritura
///    queda en la cola (la pantalla que la hizo muestra su "Guardado" de
///    siempre, que sin este aviso haría creer que ya está en el servidor).
///  - Cuántas se subieron solas al volver la conexión, y si el servidor
///    rechazó alguna (con el motivo a la vista en Configuración).
class AvisoSincronizacion extends StatefulWidget {
  final Widget child;
  const AvisoSincronizacion({super.key, required this.child});

  @override
  State<AvisoSincronizacion> createState() => _AvisoSincronizacionState();
}

class _AvisoSincronizacionState extends State<AvisoSincronizacion> {
  StreamSubscription? _subGuardadas;
  StreamSubscription? _subResultados;
  Timer? _agrupar;
  final _descripciones = <String>{};

  @override
  void initState() {
    super.initState();
    _subGuardadas = ClienteOffline.alGuardarSinRed.listen(_alGuardarSinRed);
    _subResultados = context.read<SyncService>().resultados.listen(_alSincronizar);
  }

  @override
  void dispose() {
    _subGuardadas?.cancel();
    _subResultados?.cancel();
    _agrupar?.cancel();
    super.dispose();
  }

  /// Una sola acción puede generar varias escrituras (ej. la operación y su
  /// registro en la bitácora): se juntan en un único aviso.
  void _alGuardarSinRed(String descripcion) {
    if (descripcion != 'Bitácora') _descripciones.add(descripcion);
    _agrupar?.cancel();
    _agrupar = Timer(const Duration(milliseconds: 400), () {
      if (_descripciones.isEmpty) return;
      final detalle = _descripciones.join(', ');
      _descripciones.clear();
      toastification.show(
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: const Text('Sin internet: se guardó en esta compu'),
        description: Text('$detalle. Se sube sola cuando vuelva la conexión.'),
        autoCloseDuration: const Duration(seconds: 5),
        alignment: Alignment.topCenter,
      );
    });
  }

  void _alSincronizar(ResultadoSync r) {
    if (r.subidas > 0) {
      toastification.show(
        type: ToastificationType.success,
        style: ToastificationStyle.flatColored,
        primaryColor: AppColors.primario,
        title: Text('Volvió la conexión: se ${r.subidas == 1 ? 'subió 1 registro' : 'subieron ${r.subidas} registros'} '
            'guardados sin internet.'),
        description: const Text('Las pantallas abiertas se actualizan solas.'),
        autoCloseDuration: const Duration(seconds: 5),
        alignment: Alignment.topCenter,
      );
    }
    if (r.rechazadas > 0) {
      toastification.show(
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('El servidor no aceptó ${r.rechazadas == 1 ? '1 registro' : '${r.rechazadas} registros'} '
            'hechos sin internet.'),
        description: const Text('Mirá el motivo en Configuración → Sincronización.'),
        autoCloseDuration: const Duration(seconds: 8),
        alignment: Alignment.topCenter,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Banda arriba de cada pantalla (la pone `HomeShell`), que no ocupa lugar si
/// no hay nada que avisar:
///  - **Roja, en todas las pantallas**, mientras haya algo que el servidor
///    RECHAZÓ al subir. Antes eso solo se avisaba con un mensaje que se iba
///    solo y quedaba escondido en Configuración: lo que se entregó o produjo
///    de verdad podía quedar sin registrar sin que nadie se enterara.
///  - **Ámbar**, con lo de ESTA pantalla que se hizo sin internet y todavía no
///    subió (para no hacerlo de nuevo pensando que no se guardó).
class BandaSincronizacion extends StatelessWidget {
  /// Qué pendientes son de esta pantalla (por el comienzo de su descripción,
  /// ver `ClienteOffline.describir`). null = todos (Inicio); vacía = ninguno.
  final List<String>? prefijos;
  final VoidCallback onRevisar;
  const BandaSincronizacion({super.key, required this.prefijos, required this.onRevisar});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final rechazadas = sync.operacionesConError.where((o) => !sync.esDeOtroUsuario(o)).toList();
    final p = prefijos;
    final pendientes = p == null || p.isNotEmpty
        ? sync.operacionesPendientes
            .where((o) =>
                !sync.esDeOtroUsuario(o) &&
                o.descripcion != 'Bitácora' &&
                (p == null || p.any(o.descripcion.startsWith)))
            .toList()
        : const <OperacionOffline>[];
    if (rechazadas.isEmpty && pendientes.isEmpty) return const SizedBox.shrink();

    String hora(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (rechazadas.isNotEmpty)
        _Banda(
          color: const Color(0xFFDC2626),
          icono: Icons.error_outline,
          texto: rechazadas.length == 1
              ? 'El servidor no aceptó 1 registro hecho sin internet '
                  '(${rechazadas.first.descripcion}). No quedó registrado: revisalo.'
              : 'El servidor no aceptó ${rechazadas.length} registros hechos sin internet. '
                  'No quedaron registrados: revisalos.',
          accion: 'Revisar',
          onAccion: onRevisar,
        ),
      if (pendientes.isNotEmpty)
        _Banda(
          color: const Color(0xFFB45309),
          icono: Icons.cloud_off,
          texto: 'Guardado en esta compu, se sube solo cuando vuelva internet '
              '(no hace falta repetirlo): '
              '${pendientes.take(3).map((o) => '${o.descripcion} (${hora(o.creadoEn)})').join(' · ')}'
              '${pendientes.length > 3 ? ' y ${pendientes.length - 3} más' : ''}.',
          accion: 'Ver',
          onAccion: onRevisar,
        ),
    ]);
  }
}

class _Banda extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String texto;
  final String accion;
  final VoidCallback onAccion;
  const _Banda(
      {required this.color,
      required this.icono,
      required this.texto,
      required this.accion,
      required this.onAccion});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 12.5, color: color))),
          TextButton(onPressed: onAccion, child: Text(accion)),
        ]),
      );
}
