// Prueba de humo de la app completa: que arranque (todos los providers de
// main.dart: Auth, Sync, Preferencias, Presencia) y, sin sesión abierta,
// muestre la pantalla de login.
//
// Reemplaza a la prueba de ejemplo que trae `flutter create` (buscaba el
// contador "0 / +" de la app de plantilla, que esta app nunca tuvo, así que
// fallaba siempre sin probar nada de Salvietti).
//
// No usa red ni el dispositivo: Hive en una carpeta temporal, Supabase
// apuntando a un servidor falso (cualquier pedido contesta vacío) y el plugin
// de conectividad simulado.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:salvietti_control/main.dart';
import 'package:salvietti_control/services/hive_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // connectivity_plus: "hay wifi", sin plugin real.
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    mensajero.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (llamada) async => llamada.method == 'check' ? ['wifi'] : null,
    );
    mensajero.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );

    Hive.init(Directory.systemTemp.createTempSync('salvietti_widget_test').path);
    await HiveService.abrirCajas();

    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://demo.supabase.co',
      anonKey: 'clave-de-prueba',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
    );
  });

  testWidgets('la app arranca y, sin sesión, muestra el login', (tester) async {
    await tester.pumpWidget(const SalviettiApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Salvietti Control'), findsWidgets);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);

    // Desmontar la app cierra los timers de Sync/Presencia (si quedaran
    // vivos, la prueba fallaría por "timer pendiente").
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
