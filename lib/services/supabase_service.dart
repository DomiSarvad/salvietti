import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Punto único de acceso al cliente de Supabase.
/// Las credenciales se leen de `.env` (nunca se hardcodean en el código
/// fuente para poder rotarlas sin recompilar y evitar commitear secretos).
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Límite máximo de espera para cualquier lectura online. Sin esto, si
  /// no hay internet real (aunque el dispositivo crea tener red, p. ej.
  /// wifi sin salida) el pedido puede quedar colgado indefinidamente y la
  /// pantalla no vuelve a mostrar el spinner nunca — rompiendo el
  /// requisito de poder trabajar con o sin conexión.
  static const timeoutRed = Duration(seconds: 8);

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
