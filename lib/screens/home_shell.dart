import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../services/auth_service.dart';
import '../widgets/app_chrome.dart';
import '../widgets/app_sidebar.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/inventario/screens/almacenes_screen.dart';
import '../features/recepciones/screens/recepciones_screen.dart';
import '../features/entregas/screens/entregas_screen.dart';
import '../features/solicitudes/screens/solicitudes_screen.dart';
import '../features/compras/screens/compras_screen.dart';
import '../features/informes/screens/informes_screen.dart';
import '../features/soplado/screens/soplado_screen.dart';
import '../features/jarabes/screens/jarabes_screen.dart';
import '../features/calidad/screens/calidad_screen.dart';
import '../features/llenadora/screens/llenadora_screen.dart';
import '../features/codificacion/screens/codificacion_screen.dart';
import '../features/registro_salidas/screens/salidas_screen.dart';
import '../features/mermas/screens/mermas_screen.dart';
import '../features/soda_caustica/screens/soda_screen.dart';
import '../features/informe_gerente/screens/informe_screen.dart';
import 'ayuda/manual_screen.dart';
import 'configuracion/configuracion_screen.dart';
import 'produccion/produccion_planner_screen.dart';
import 'historial/historial_screen.dart';
import 'usuarios/usuarios_screen.dart';
import '../features/notificaciones/repositories/campana_repository.dart';
import '../features/notificaciones/services/campana_service.dart';
import '../features/notificaciones/widgets/campana_flotante.dart';

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
  // Con qué almacén abre Almacenes al entrar desde una tarjeta del Inicio
  // (null = el primero que el rol pueda ver, al entrar desde el menú).
  String? _almacenInicial;
  // Con qué sabor abre Jarabes (y listo para calcular el preparado) al
  // entrar desde un producto de Producción del día (null = normal).
  String? _saborJarabesInicial;

  void _navegar(String ruta) => setState(() {
        _ruta = ruta;
        _almacenInicial = null;
        _saborJarabesInicial = null;
      });

  void _abrirAlmacen(String almacenId) => setState(() {
        _ruta = 'almacenes';
        _almacenInicial = almacenId;
        _saborJarabesInicial = null;
      });

  void _abrirJarabesConSabor(String sabor) => setState(() {
        _ruta = 'jarabes';
        _almacenInicial = null;
        _saborJarabesInicial = sabor;
      });

  void _abrirProduccion() => setState(() {
        _ruta = 'produccion';
        _almacenInicial = null;
        _saborJarabesInicial = null;
      });

  Widget _pantalla() {
    switch (_ruta) {
      case 'almacenes':
        return AlmacenesScreen(almacenInicial: _almacenInicial);
      case 'recepciones':
        return const RecepcionesScreen();
      case 'entregas':
        return const EntregasScreen();
      case 'solicitudes':
        return const SolicitudesScreen();
      case 'soplado':
        return const SopladoScreen();
      case 'jarabes':
        return JarabesScreen(saborInicial: _saborJarabesInicial);
      case 'calidad':
        return const CalidadScreen();
      case 'llenadora':
        return const LlenadoraScreen();
      case 'codificacion':
        return const CodificacionScreen();
      case 'salidas':
        return const SalidasScreen();
      case 'mermas':
        return const MermasScreen();
      case 'soda_caustica':
        return const SodaScreen();
      case 'informe_gerente':
        return const InformeScreen();
      case 'informes':
        return const InformesScreen();
      case 'compras':
        return const ComprasScreen();
      case 'produccion':
        return ProduccionPlannerScreen(onIrAJarabes: _abrirJarabesConSabor);
      case 'historial':
        return const HistorialScreen();
      case 'usuarios':
        return const UsuariosScreen();
      case 'configuracion':
        return const ConfiguracionScreen();
      case 'manual':
        return const ManualScreen();
      default:
        return DashboardScreen(
            onAbrirInventario: _abrirAlmacen, onAbrirProduccion: _abrirProduccion);
    }
  }

  static const _titulos = {
    'dashboard': 'Inicio',
    'almacenes': 'Almacenes',
    'recepciones': 'Recepciones',
    'entregas': 'Entregas',
    'solicitudes': 'Solicitudes',
    'soplado': 'Soplado',
    'jarabes': 'Jarabes',
    'calidad': 'Control de Calidad',
    'llenadora': 'Llenadora',
    'codificacion': 'Codificación',
    'salidas': 'Registro de salidas',
    'mermas': 'Mermas',
    'soda_caustica': 'Soda Cáustica',
    'informe_gerente': 'Informe de Producción',
    'informes': 'Informes',
    'compras': 'Pedidos de compra',
    'produccion': 'Producción del día',
    'historial': 'Historial / Bitácora',
    'usuarios': 'Usuarios',
    'configuracion': 'Configuración',
    'manual': 'Manual de usuario',
  };

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual;
    if (usuario == null) return const SizedBox.shrink();

    final anchoAngosto = MediaQuery.of(context).size.width < 900;

    // Contenido común: migas de pan + la pantalla de la sección.
    final contenido = Column(
      children: [
        AppBreadcrumb(
          titulo: _titulos[_ruta] ?? '',
          esInicio: _ruta == 'dashboard',
          onInicio: () => _navegar('dashboard'),
        ),
        Expanded(child: _pantalla()),
      ],
    );

    // Campana flotante (abajo a la derecha, del lado contrario al menú): lo
    // pendiente de cada persona. Vive mientras dure la sesión de este usuario.
    Widget conCampana(Widget pantalla) => ChangeNotifierProvider(
          key: ValueKey(usuario.id),
          create: (_) => CampanaService(SupabaseCampanaRepository(), usuario)..iniciar(),
          child: pantalla,
        );
    final campana = CampanaFlotante(onNavegar: _navegar);

    if (anchoAngosto) {
      return conCampana(Scaffold(
        key: _scaffoldKey,
        floatingActionButton: campana,
        backgroundColor: AppColors.fondo,
        drawer: Drawer(
          backgroundColor: const Color(0xFF17221D),
          child: SafeArea(
            child: AppSidebar(
              rutaActual: _ruta,
              onNavegar: (r) {
                _navegar(r);
                Navigator.pop(context);
              },
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              AppTopBar(
                onNavegar: _navegar,
                onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(child: contenido),
              const AppFooter(),
            ],
          ),
        ),
      ));
    }

    return conCampana(Scaffold(
      backgroundColor: AppColors.fondo,
      floatingActionButton: campana,
      body: Column(
        children: [
          AppTopBar(onNavegar: _navegar),
          Expanded(
            child: Row(
              children: [
                AppSidebar(rutaActual: _ruta, onNavegar: _navegar),
                Expanded(child: contenido),
              ],
            ),
          ),
          const AppFooter(),
        ],
      ),
    ));
  }
}
