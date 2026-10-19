import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import '../core/constants.dart';
import '../services/cliente_offline.dart';
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
        description: const Text('Si una pantalla no lo muestra todavía, salí y volvé a entrar.'),
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
