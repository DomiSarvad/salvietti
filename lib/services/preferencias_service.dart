import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';

/// Preferencias de la app (no del perfil del usuario): cosas de
/// "Configuración" que no dependen de la cuenta con la que se entra, sino
/// del dispositivo — hoy solo el tamaño de letra. Se guardan en
/// `HiveBoxes.preferencias` y se aplican al toque en toda la app (ver
/// `builder` de `MaterialApp` en main.dart), sin reiniciar.
class PreferenciasService extends ChangeNotifier {
  static const _claveEscalaTexto = 'escala_texto';

  /// 0.9 = chico, 1.0 = normal, 1.15 = grande.
  double escalaTexto = 1.0;

  Box get _caja => Hive.box(HiveBoxes.preferencias);

  PreferenciasService() {
    escalaTexto = (_caja.get(_claveEscalaTexto) as num?)?.toDouble() ?? 1.0;
  }

  Future<void> cambiarEscalaTexto(double valor) async {
    escalaTexto = valor;
    notifyListeners();
    await _caja.put(_claveEscalaTexto, valor);
  }
}
