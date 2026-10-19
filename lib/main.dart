import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:toastification/toastification.dart';
import 'core/constants.dart';
import 'features/presencia/repositories/presencia_repository.dart';
import 'features/presencia/services/presencia_service.dart';
import 'services/auth_service.dart';
import 'services/hive_service.dart';
import 'services/preferencias_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/perfil/completar_datos_screen.dart';
import 'widgets/aviso_sincronizacion.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Habilita video_player en Windows/Linux (plataformas sin soporte nativo);
  // en el resto de plataformas no hace nada.
  fvp.registerWith();
  await initializeDateFormatting('es_BO', null);
  await HiveService.init(); // almacenamiento local offline-first
  await SupabaseService.init(); // backend en la nube
  runApp(const SalviettiApp());
}

class SalviettiApp extends StatelessWidget {
  const SalviettiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..recuperarSesion()),
        // Proxy en vez de Provider simple: SyncService necesita poder
        // pedirle a AuthService que suba la foto de perfil pendiente al
        // reconectar (ver SyncService.vincularAuth).
        ChangeNotifierProxyProvider<AuthService, SyncService>(
          create: (_) => SyncService()..iniciarMonitoreo(),
          update: (_, auth, sync) => sync!..vincularAuth(auth),
        ),
        ChangeNotifierProvider(create: (_) => PreferenciasService()),
        // Presencia de las áreas (quién está sin internet): vive toda la
        // sesión, avisa cada minuto y lee el estado de las demás.
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) {
            final sync = ctx.read<SyncService>();
            return PresenciaService(
              SupabasePresenciaRepository(),
              pendientes: () => sync.pendientes,
              usuarioActual: () => SupabaseService.currentUser?.id,
              hayRed: () => sync.online,
              cambios: sync,
            )..iniciar();
          },
        ),
      ],
      child: ToastificationWrapper(
        child: Consumer<PreferenciasService>(
          builder: (context, prefs, _) => MaterialApp(
            title: 'Salvietti Control',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: AppColors.primario,
              scaffoldBackgroundColor: AppColors.fondo,
            ),
            // Tamaño de letra elegido en Configuración: se aplica a toda la
            // app envolviendo el árbol con un MediaQuery propio, sin tener
            // que tocar cada pantalla.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(prefs.escalaTexto)),
              // Avisos de "guardado sin internet" / "se subió lo pendiente".
              child: AvisoSincronizacion(child: child!),
            ),
            home: const _RaizApp(),
          ),
        ),
      ),
    );
  }
}

/// Decide si mostrar el login o el shell principal según haya sesión.
class _RaizApp extends StatelessWidget {
  const _RaizApp();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.autenticado) return const LoginScreen();
    // Primer ingreso: antes de usar el sistema debe completar sus datos.
    if (auth.datosPendientes) return const CompletarDatosScreen();
    return const HomeShell();
  }
}
