import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:salvietti_control/features/informes/models/informes_modelos.dart';
import 'package:salvietti_control/features/informes/services/informes_export_service.dart';

InformeArea _informe({bool vacio = false}) {
  final r = RangoInforme.de(PeriodoInforme.semana, DateTime(2026, 10, 23));
  return InformeArea(
    area: AreaInforme.soplado,
    rango: r,
    kpis: const [KpiInforme('Botellas sopladas', '2.000'), KpiInforme('% de merma', '4,0 %', alerta: true)],
    tituloGrafico: 'Botellas y merma',
    series: [
      SerieInforme('Sopladas', vacio ? List.filled(7, 0) : [0, 1000, 1000, 0, 0, 0, 0]),
      SerieInforme('Merma', vacio ? List.filled(7, 0) : [0, 40, 20, 0, 0, 0, 0]),
    ],
    tituloTabla: 'Por sabor',
    columnas: const ['Sabor', 'Producido'],
    filas: vacio ? const [] : const [['Papaya', '1.000'], ['Ross', '1.000']],
    nota: 'Nota de prueba',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_BO'));

  test('genera el PDF con gráfico, y también sin datos', () async {
    final pdf = await InformesExportService.pdf(_informe(), responsable: 'Gerente');
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    final vacio = await InformesExportService.pdf(_informe(vacio: true), responsable: 'Gerente');
    expect(vacio, isNotEmpty);
  });

  test('genera el Excel con los números como números', () {
    final bytes = InformesExportService.excel(_informe(), responsable: 'Gerente');
    final hoja = xls.Excel.decodeBytes(bytes)['Informe'];
    final valores = hoja.rows.expand((f) => f).whereType<xls.Data>().map((c) => c.value).toList();
    final numeros = [
      ...valores.whereType<xls.DoubleCellValue>().map((v) => v.value),
      ...valores.whereType<xls.IntCellValue>().map((v) => v.value.toDouble()),
    ];
    expect(numeros, contains(1000)); // número, no texto: se puede sumar o graficar en Excel
    expect(valores.whereType<xls.TextCellValue>().map((v) => v.value.text), contains('Papaya'));
  });
}
