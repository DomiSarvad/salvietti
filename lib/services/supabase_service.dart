import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cliente_offline.dart';

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
      // Sin internet: lecturas desde la copia local y escrituras a la cola
      // de Hive, para todos los módulos a la vez (ver ClienteOffline).
      httpClient: ClienteOffline(),
    );
  }

  /// Trae TODAS las filas de una consulta, de a [pagina] (Supabase corta
  /// cada respuesta en 1000 filas). Para catálogos que se buscan en memoria
  /// (`CatalogoLocal`): [consulta] recibe el rango y arma la consulta.
  static Future<List<Map<String, dynamic>>> todasLasFilas(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(int desde, int hasta) consulta, {
    int pagina = 1000,
  }) async {
    final todas = <Map<String, dynamic>>[];
    for (var desde = 0;; desde += pagina) {
      final filas = await consulta(desde, desde + pagina - 1).timeout(timeoutRed);
      todas.addAll(filas);
      if (filas.length < pagina) return todas;
    }
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get haySesion => currentUser != null;
}
