import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard/dashboard_screen.dart';
import 'inventario/inventario_list_screen.dart';
import 'produccion/produccion_planner_screen.dart';
import 'historial/historial_screen.dart';
import 'usuarios/usuarios_screen.dart';

/// Contenedor principal luego del login: muestra el sidebar y cambia
/// de sección sin recargar toda la app (SPA-like), tanto en escritorio
/// (layout con sidebar fijo) como en móvil (drawer deslizable).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _ruta = 'dashboard';

  Widget _pantalla() {
    switch (_ruta) {
      case 'inventario':
        return const InventarioListScreen();
      case 'produccion':
        return const ProduccionPlannerScreen();
      case 'historial':
        return const HistorialScreen();
      case 'usuarios':
        return const UsuariosScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual;
    if (usuario == null) return const SizedBox.shrink();

    final anchoAngosto = MediaQuery.of(context).size.width < 900;

    if (anchoAngosto) {
      return Scaffold(
        backgroundColor: AppColors.fondo,
        appBar: AppBar(
            title: const Text('Salvietti Control'),
            backgroundColor: AppColors.primario),
        drawer: Drawer(
          child: AppSidebar(
            rutaActual: _ruta,
            onNavegar: (r) {
              setState(() => _ruta = r);
              Navigator.pop(context);
            },
          ),
        ),
        body: _pantalla(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.fondo,
      body: Row(
        children: [
          AppSidebar(
              rutaActual: _ruta, onNavegar: (r) => setState(() => _ruta = r)),
          Expanded(child: _pantalla()),
        ],
      ),
    );
  }
}
