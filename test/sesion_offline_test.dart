import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:salvietti_control/core/constants.dart';
import 'package:salvietti_control/services/sesion_offline.dart';
import 'package:salvietti_control/services/sesion_inactividad.dart';

const _perfil = {
  'id': 'u-1',
  'nombre_completo': 'Ana Soplado',
  'rol': 'soplado',
  'activo': true,
};

Future<void> _recordar([String clave = 'Clave123']) => SesionOffline.recordar(
      correo: 'Ana@Salvietti.com',
      password: clave,
      perfil: _perfil,
      permisos: {'soplado:ver', 'soplado:crear'},
    );

Matcher _errorQueDice(String texto) =>
    throwsA(isA<ErrorSesionOffline>().having((e) => e.mensaje, 'mensaje', contains(texto)));

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('sesion_offline_test').path);
    await Hive.openBox(HiveBoxes.sesion);
  });

  setUp(() => Hive.box(HiveBoxes.sesion).clear());

  test('con la contraseña correcta devuelve el perfil y los permisos guardados', () async {
    await _recordar();
    final r = await SesionOffline.verificar('ana@salvietti.com ', 'Clave123');
    expect(r.perfil['nombre_completo'], 'Ana Soplado');
    expect(r.permisos, {'soplado:ver', 'soplado:crear'});
  });

  test('no guarda la contraseña en la compu, solo una huella', () async {
    await _recordar();
    final guardado = Hive.box(HiveBoxes.sesion).values.join(' ');
    expect(guardado, isNot(contains('Clave123')));
  });

  test('rechaza una contraseña incorrecta', () async {
    await _recordar();
    expect(() => SesionOffline.verificar('ana@salvietti.com', 'clave123'),
        _errorQueDice('incorrectos'));
  });

  test('quien nunca entró con internet en esta compu no puede entrar sin internet', () async {
    expect(() => SesionOffline.verificar('otro@salvietti.com', 'x'), _errorQueDice('no entró nunca'));
  });

  test('5 contraseñas mal seguidas bloquean 5 minutos, aunque después pongan la buena', () async {
    await _recordar();
    final t0 = DateTime(2026, 10, 23, 9);
    for (var i = 0; i < 5; i++) {
      await expectLater(
          SesionOffline.verificar('ana@salvietti.com', 'mala', ahora: () => t0),
          throwsA(isA<ErrorSesionOffline>()));
    }
    expect(() => SesionOffline.verificar('ana@salvietti.com', 'Clave123', ahora: () => t0),
        _errorQueDice('Esperá'));
    // Pasado el bloqueo, la buena entra.
    final r = await SesionOffline.verificar('ana@salvietti.com', 'Clave123',
        ahora: () => t0.add(const Duration(minutes: 6)));
    expect(r.perfil['id'], 'u-1');
  });

  test('vence a los 30 días sin entrar con internet', () async {
    await _recordar();
    expect(
        () => SesionOffline.verificar('ana@salvietti.com', 'Clave123',
            ahora: () => DateTime.now().add(const Duration(days: 31))),
        _errorQueDice('30 días'));
  });

  test('si se vuelve a entrar con internet con otra contraseña, vale la nueva', () async {
    await _recordar('Vieja1');
    await _recordar('Nueva2');
    expect(() => SesionOffline.verificar('ana@salvietti.com', 'Vieja1'), _errorQueDice('incorrectos'));
    expect((await SesionOffline.verificar('ana@salvietti.com', 'Nueva2')).perfil['id'], 'u-1');
  });

  test('encuentra el perfil guardado por id (reabrir la app sin internet)', () async {
    await _recordar();
    expect(SesionOffline.perfilDe('u-1')?.perfil['rol'], 'soplado');
    expect(SesionOffline.perfilDe('u-2'), isNull);
  });

  test('recuerda si falta cargar los datos personales, y deja de pedirlos al completarlos', () async {
    await SesionOffline.recordar(
        correo: 'nuevo@salvietti.com', password: 'Clave123', perfil: _perfil, permisos: null,
        datosCompletos: false);
    expect((await SesionOffline.verificar('nuevo@salvietti.com', 'Clave123')).datosCompletos, isFalse);
    await SesionOffline.marcarDatosCompletos('u-1'); // los cargó sin internet
    expect((await SesionOffline.verificar('nuevo@salvietti.com', 'Clave123')).datosCompletos, isTrue);
  });

  group('ausencia', () {
    final t0 = DateTime(2026, 10, 23, 8);
    test('sin registro previo no echa a nadie', () {
      expect(SesionInactividad.vencida(ahora: t0), isFalse);
    });
    test('pide ingresar de nuevo pasado el límite, no antes', () async {
      await SesionInactividad.registrarActividad(ahora: t0);
      expect(SesionInactividad.vencida(ahora: t0.add(const Duration(minutes: 59))), isFalse);
      expect(SesionInactividad.vencida(ahora: t0.add(SesionInactividad.limite + const Duration(minutes: 1))), isTrue);
    });
  });
}
