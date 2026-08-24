import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/login_screen.dart';
import 'services/database_service.dart';
import 'services/hive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Carga de variables de entorno
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ Error al cargar el archivo .env: $e');
  }

  // 2. Inicialización de Almacenamiento Local (Hive)
  await HiveService.init();

  // 3. Obtención y validación de credenciales
  final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    debugPrint(
      '❌ ERROR CRÍTICO: SUPABASE_URL o SUPABASE_ANON_KEY están vacías en el .env',
    );
    runApp(
      const _SupabaseConfigErrorApp(
        message:
            'Falta la configuración de Supabase en .env. Revisa SUPABASE_URL y SUPABASE_ANON_KEY.',
      ),
    );
    return;
  }

  debugPrint('✅ Inicializando Supabase en: $supabaseUrl');

  // 4. Inicializar Supabase Client
  await DatabaseService.initSupabase(
    url: supabaseUrl,
    publishableKey: supabaseKey,
  );

  runApp(const SalviettiApp());
}

class _SupabaseConfigErrorApp extends StatelessWidget {
  const _SupabaseConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Configuración de Supabase incompleta',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SalviettiApp extends StatelessWidget {
  const SalviettiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salvietti Planta',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}
