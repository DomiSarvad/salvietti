import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/shared/busqueda_local.dart';

void main() {
  final items = ['Tapa Short Negra', 'Cápsula negra', 'Preforma 28 g', 'Etiqueta Fresa', 'Tapa azul'];
  final indice = IndiceBusqueda(items, (s) => s);

  test('exige todas las palabras, en cualquier orden, sin importar tildes', () {
    expect(indice.buscar('negra tapa'), ['Tapa Short Negra']);
    expect(indice.buscar('CAPSULA'), ['Cápsula negra']);
    expect(indice.buscar('capsula verde'), isEmpty);
  });

  test('pone primero lo que empieza con lo escrito', () {
    // "neg" empieza una palabra en las dos; "a" está dentro de muchas.
    expect(indice.buscar('ta').first, 'Tapa Short Negra');
    expect(indice.buscar('fresa'), ['Etiqueta Fresa']);
  });

  test('sin texto devuelve los primeros, respetando el límite y el filtro', () {
    expect(indice.buscar('', limite: 2), hasLength(2));
    expect(indice.buscar('tapa', donde: (s) => !s.contains('azul')), ['Tapa Short Negra']);
  });

  test('CatalogoLocal consulta al servidor una sola vez para muchas búsquedas', () async {
    var cargas = 0;
    final catalogo = CatalogoLocal<String>(() async {
      cargas++;
      return items;
    }, (s) => s);

    // Dos búsquedas a la vez (dos letras rápidas) comparten la misma carga.
    await Future.wait([catalogo.buscar('t'), catalogo.buscar('ta')]);
    expect(await catalogo.buscar('tapa n'), ['Tapa Short Negra']);
    expect(cargas, 1);

    catalogo.invalidar();
    await catalogo.buscar('x');
    expect(cargas, 2);
  });
}
