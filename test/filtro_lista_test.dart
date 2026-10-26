import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:salvietti_control/shared/filtros/filtro_lista.dart';
import 'package:salvietti_control/shared/reportes/reporte_tabla.dart';
import 'package:salvietti_control/utils/formatters.dart';

class _R {
  final String texto;
  final DateTime? fecha;
  const _R(this.texto, this.fecha);
}

final _datos = [
  _R('Papaya 2,5 L · Ana', DateTime(2026, 10, 1, 9)),
  _R('Ross 2 L · José', DateTime(2026, 10, 15, 23, 59)),
  _R('Piña 3 L · Ana', DateTime(2026, 10, 31, 8)),
  const _R('Sin fecha', null),
];

List<String> _aplicar(FiltroLista f) =>
    f.aplicar(_datos, texto: (r) => r.texto, fecha: (r) => r.fecha).map((r) => r.texto).toList();

void main() {
  setUpAll(() => initializeDateFormatting('es_BO'));

  test('sin filtros devuelve todo', () {
    expect(_aplicar(const FiltroLista()), hasLength(4));
    expect(const FiltroLista().activo, isFalse);
  });

  test('texto: todas las palabras, en cualquier orden, sin tildes ni mayúsculas', () {
    expect(_aplicar(const FiltroLista(texto: 'ana PINA')), ['Piña 3 L · Ana']);
    expect(_aplicar(const FiltroLista(texto: 'ana')), hasLength(2));
    expect(_aplicar(const FiltroLista(texto: 'ana ross')), isEmpty);
  });

  test('Desde/Hasta incluyen el día entero; sin fecha queda afuera si hay rango', () {
    final f = FiltroLista(desde: DateTime(2026, 10, 1), hasta: DateTime(2026, 10, 15));
    expect(_aplicar(f), ['Papaya 2,5 L · Ana', 'Ross 2 L · José']);
    expect(_aplicar(FiltroLista(desde: DateTime(2026, 10, 16))), ['Piña 3 L · Ana']);
  });

  test('describe los filtros para el encabezado del reporte', () {
    expect(const FiltroLista().describir(), 'Sin filtros (todo)');
    expect(FiltroLista(texto: 'papaya', desde: DateTime(2026, 10, 1)).describir(),
        'Búsqueda: "papaya"   ·   Desde 01/10/2026');
  });

  test('números en formato es-BO: punto para miles, coma para decimales', () {
    expect(fmtNum(1234.5), '1.234,50');
    expect(fmtNum(1000000, decimales: 0), '1.000.000');
    expect(fmtNum(-12.3), '-12,30');
    expect(fmtNum(0.5, decimales: 1), '0,5');
  });

  test('el reporte muestra texto lindo y en Excel deja los números como números', () {
    final r = ReporteTabla(
      titulo: 'Prueba',
      filtros: 'Sin filtros (todo)',
      columnas: const ['Fecha', 'Sabor', 'Botellas'],
      filas: [
        [DateTime(2026, 10, 1), 'Papaya', 1234.5],
        [DateTime(2026, 10, 2, 14, 30), null, 2000],
      ],
    );
    expect(r.numericas, {2});
    expect(ReporteTabla.texto(1234.5), '1.234,50');
    expect(ReporteTabla.texto(null), '—');
    expect(ReporteTabla.texto(DateTime(2026, 10, 1)), '01/10/2026');

    final hoja = xls.Excel.decodeBytes(ReporteTablaExport.excel(r, responsable: 'X'))['Reporte'];
    final valores = hoja.rows.expand((f) => f).whereType<xls.Data>().map((c) => c.value).toList();
    final numeros = [
      ...valores.whereType<xls.DoubleCellValue>().map((v) => v.value),
      ...valores.whereType<xls.IntCellValue>().map((v) => v.value.toDouble()),
    ];
    expect(numeros, containsAll([1234.5, 2000.0]));
  });
}
