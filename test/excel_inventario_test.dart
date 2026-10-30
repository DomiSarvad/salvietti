import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/features/inventario/services/excel_inventario.dart';
import 'package:salvietti_control/features/inventario/models/item_inventario.dart';

/// Arma un .xlsx en memoria con estas filas (la primera, encabezados).
Uint8List _excel(List<List<Object?>> filas) {
  final libro = xls.Excel.createExcel();
  libro.rename('Sheet1', 'Inventario');
  final hoja = libro['Inventario'];
  for (var r = 0; r < filas.length; r++) {
    for (var c = 0; c < filas[r].length; c++) {
      final v = filas[r][c];
      if (v == null) continue;
      hoja.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
          v is num ? xls.DoubleCellValue(v.toDouble()) : xls.TextCellValue('$v'));
    }
  }
  return Uint8List.fromList(libro.encode()!);
}

const _ctx = ContextoExcel(
  rutas: {1: 'Tapas', 2: 'Tapas › Negro', 3: 'Preformas › Negro', 4: 'Limpieza'},
  porCodigo: {'IN-0001': 10},
  porDetalle: {'escoba': 11},
);

void main() {
  test('las columnas que el sistema no tiene se avisan y se guardan como otros datos', () {
    final l = leerExcelInventario(
        _excel([
          ['Detalle', 'Categoría', 'Proveedor', 'Precio', 'Color'],
          ['Jabón', 'Limpieza', 'Química Sur', 12.5, 'Azul'],
          ['Balde', 'Limpieza', null, null, null],
        ]),
        _ctx);
    expect(l.columnasExtra, ['Proveedor', 'Precio']);
    final jabon = l.nuevos.first.nuevo!;
    expect(jabon.atributos, {'color': 'Azul', 'Proveedor': 'Química Sur', 'Precio': '12.5'});
    expect(jabon.otrosDatos.keys, ['Proveedor', 'Precio']);
    expect(l.nuevos[1].nuevo!.atributos, isEmpty);
  });

  test('crea los nuevos, reconoce los que ya existen y lista los errores por fila', () {
    final l = leerExcelInventario(
        _excel([
          ['Detalle', 'Categoría', 'Unidad', 'Stock', 'Stock mínimo'],
          ['Tapa Short Negra', 'Tapas > Negro', 'pza', 5000, 1000],
          ['Jabón líquido', 'limpieza', 'litros', null, null],
          ['Escoba', 'Limpieza', 'UNI', 7, null], // ya existe: solo stock
          ['Algo raro', 'No existe', 'UNI', null, null],
          ['Otra negra', 'Negro', 'UNI', null, null], // "Negro" está dos veces
          ['Tapa Short Negra', 'Tapas › Negro', 'PZA', null, null], // repetida
          [null, null, null, null, null], // vacía
        ]),
        _ctx);
    expect(l.errorGeneral, isNull);
    expect(l.nuevos.map((f) => f.detalle), ['Tapa Short Negra', 'Jabón líquido']);
    expect(l.nuevos.first.nuevo!.categoriaId, 2);
    expect(l.nuevos.first.nuevo!.unidad, 'PZA');
    expect(l.nuevos.first.nuevo!.stockMinimo, 1000);
    expect(l.nuevos[1].nuevo!.unidad, 'L');
    expect(l.existentes.single.existenteId, 11);
    expect(l.existentes.single.stock, 7);
    expect(l.conError.map((f) => f.fila), [5, 6, 7]);
    expect(l.conError[1].error, contains('ruta completa'));
    expect(l.conStock, 2);
  });

  test('sin columna Detalle o Categoría avisa y no importa nada', () {
    expect(leerExcelInventario(_excel([['Nombre del jefe'], ['x']]), _ctx).errorGeneral, contains('Detalle'));
    expect(leerExcelInventario(_excel([['Detalle'], ['x']]), _ctx).errorGeneral, contains('Categoría'));
    expect(leerExcelInventario(Uint8List.fromList([1, 2, 3]), _ctx).errorGeneral, contains('.xlsx'));
  });

  test('la plantilla general trae todas las columnas y se puede volver a leer', () {
    const tapa = ItemInventario(
        id: 3, codigo: 'IN-0003', categoriaId: 1, detalle: 'Tapa Short Negra 28mm', unidad: 'PZA');
    final bytes = plantillaExcelInventario('Almacén General', ['Tapas', 'Tapas › Negro'],
        ejemplo: (tapa, 'Tapas'));
    final enc = xls.Excel.decodeBytes(bytes).tables['Inventario']!.rows.first;
    expect(enc.where((c) => c != null).length, 15);
    final l = leerExcelInventario(bytes, _ctx);
    expect(l.errorGeneral, isNull);
    expect(l.nuevos.single.detalle, 'Tapa Short Negra 28mm'); // en _ctx no existe todavía
  });

  test('plantilla de una categoría: solo sus columnas y de ejemplo un ítem que ya existe', () {
    const termo = ItemInventario(
        id: 7, codigo: 'IN-0007', categoriaId: 1, detalle: 'Termo 50cm', unidad: 'KG',
        atributos: {'ancho_mm': 500, 'micronaje': 50});
    expect(columnasUsadas([termo]), {'ancho', 'micronaje'});
    final bytes = plantillaExcelInventario('Almacén General', ['Tapas'],
        columnas: columnasUsadas([termo]), ejemplo: (termo, 'Tapas'), categoria: 'Tapas');
    final enc = [for (final c in xls.Excel.decodeBytes(bytes).tables['Inventario']!.rows.first) c?.value.toString()];
    expect(enc, containsAll(['Ancho (mm)', 'Micronaje']));
    expect(enc, isNot(contains('Color')));
    final l = leerExcelInventario(bytes, const ContextoExcel(rutas: {1: 'Tapas'}, porCodigo: {'IN-0007': 7}, porDetalle: {}));
    expect(l.nuevos, isEmpty);
    expect(l.existentes.single.stock, isNull);
  });
}
