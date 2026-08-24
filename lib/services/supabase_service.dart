import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Punto único de acceso al cliente de Supabase.
/// Las credenciales se leen de `.env` (nunca se hardcodean en el código
/// fuente para poder rotarlas sin recompilar y evitar commitear secretos).
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get haySesion => currentUser != null;
}
