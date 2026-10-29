import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:salvietti_control/core/constants.dart';
import 'package:salvietti_control/shared/ayuda/tour_ayuda.dart';
import 'package:salvietti_control/shared/ayuda/tours_vistos_repository.dart';

/// Servidor falso: lo que cada usuario ya vio.
class _Repo implements ToursVistosRepository {
  final Set<String> guardados;
  _Repo([Set<String>? inicial]) : guardados = inicial ?? {};

  @override
  Future<Set<String>> vistos() async => {...guardados};
  @override
  Future<void> marcar(String idTour) async => guardados.add(idTour);
  @override
  Future<void> borrarTodos() async => guardados.clear();
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('tour_ayuda_test').path);
    await Hive.openBox(HiveBoxes.preferencias);
  });

  setUp(() => Hive.box(HiveBoxes.preferencias).clear());

  test('lo visto en otra compu (servidor) no vuelve a salir solo', () async {
    await TourAyuda.cargarDelUsuario('u1', _Repo({'almacenes'}));
    expect(TourAyuda.yaVisto('almacenes'), isTrue);
    expect(TourAyuda.yaVisto('jarabes'), isFalse);
  });

  test('cada usuario tiene lo suyo en la misma compu', () async {
    await TourAyuda.cargarDelUsuario('u1', _Repo({'inicio'}));
    expect(TourAyuda.yaVisto('inicio'), isTrue);
    TourAyuda.olvidarUsuario();
    await TourAyuda.cargarDelUsuario('u2', _Repo());
    expect(TourAyuda.yaVisto('inicio'), isFalse);
  });

  test('sin red queda lo recordado en la compu', () async {
    await Hive.box(HiveBoxes.preferencias).put('tour_u1_mermas', true);
    TourAyuda.usarSinServidor('u1');
    expect(TourAyuda.yaVisto('mermas'), isTrue);
  });
}
