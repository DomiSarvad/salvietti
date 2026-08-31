import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'services/auth_service.dart';
import 'services/hive_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  await initializeDateFormatting('es_BO', null);
  WidgetsFlutterBinding.ensureInitialized();
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
      ],
      child: MaterialApp(
        title: 'Salvietti Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: AppColors.primario,
          scaffoldBackgroundColor: AppColors.fondo,
        ),
        home: const _RaizApp(),
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
    return auth.autenticado ? const HomeShell() : const LoginScreen();
  }
}
