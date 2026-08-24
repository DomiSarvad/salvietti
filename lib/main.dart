import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'services/auth_service.dart';
import 'services/hive_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();       // almacenamiento local offline-first
  await SupabaseService.init();   // backend en la nube
  runApp(const SalviettiApp());
}

class SalviettiApp extends StatelessWidget {
  const SalviettiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..recuperarSesion()),
        ChangeNotifierProvider(create: (_) => SyncService()..iniciarMonitoreo()),
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
