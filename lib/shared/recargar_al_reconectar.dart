import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../services/sync_service.dart';

/// Vuelve a cargar la pantalla sola cuando regresa internet o se sube lo que
/// estaba en la cola (`SyncService.alHaberDatosNuevos`). Sin esto, una pantalla
/// abierta durante el corte seguía mostrando la copia guardada hasta salir y
/// volver a entrar. Para las pantallas sin tiempo real (las que tienen
/// `escucharTablas` ya recargan al reconectar el canal).
///
/// Va justo debajo del `ChangeNotifierProvider` del service, así
/// [alReconectar] puede leerlo: `(c) => c.read<XService>().recargar()`.
class RecargarAlReconectar extends StatefulWidget {
  final Future<void> Function(BuildContext context) alReconectar;
  final Widget child;
  const RecargarAlReconectar({super.key, required this.alReconectar, required this.child});

  @override
  State<RecargarAlReconectar> createState() => _RecargarAlReconectarState();
}

class _RecargarAlReconectarState extends State<RecargarAlReconectar> {
  StreamSubscription<void>? _sub;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    // Volver la red y terminar de subir la cola llegan casi juntos: una sola recarga.
    _sub = context.read<SyncService>().alHaberDatosNuevos.listen((_) {
      _espera?.cancel();
      _espera = Timer(const Duration(seconds: 1), () {
        if (mounted) widget.alReconectar(context);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _espera?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
