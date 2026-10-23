import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/sesion_inactividad.dart';

/// Lleva la cuenta de cuándo se usó la app por última vez y cierra la sesión
/// si se vuelve a ella después de [SesionInactividad.limite] (ver esa clase).
/// Envuelve toda la app en `main.dart`.
class VigilanteSesion extends StatefulWidget {
  final Widget child;
  const VigilanteSesion({super.key, required this.child});

  @override
  State<VigilanteSesion> createState() => _VigilanteSesionState();
}

class _VigilanteSesionState extends State<VigilanteSesion> with WidgetsBindingObserver {
  Timer? _cadaMinuto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mientras está abierta y con alguien adentro, sigue "en uso". En
    // escritorio cerrar la ventana a veces no avisa: este minuto a minuto es
    // lo que queda como última actividad.
    _cadaMinuto = Timer.periodic(const Duration(minutes: 1), (_) => _anotarSiHaySesion());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cadaMinuto?.cancel();
    super.dispose();
  }

  void _anotarSiHaySesion() {
    if (context.read<AuthService>().autenticado) {
      SesionInactividad.registrarActividad().catchError((_) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final auth = context.read<AuthService>();
    if (!auth.autenticado) return;
    switch (estado) {
      case AppLifecycleState.resumed:
        // Volvió a la app: ¿cuánto estuvo afuera?
        if (SesionInactividad.vencida()) {
          auth.cerrarPorInactividad();
        } else {
          SesionInactividad.registrarActividad().catchError((_) {});
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Se va: desde acá empieza a contar el tiempo afuera.
        SesionInactividad.registrarActividad().catchError((_) {});
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
