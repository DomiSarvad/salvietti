import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/archivo_service.dart';
import '../../../utils/formatters.dart';
import '../models/informes_modelos.dart';

/// Exporta un [InformeArea] a PDF (con gráfico de barras) o a Excel, con lo
/// mismo que se ve en pantalla. Mismo estilo de marca que el reporte de
/// inventario: logo de marca de agua, encabezado verde, pie paginado.
class InformesExportService {
  static const _verde = PdfColor.fromInt(0xFF1B5E3A);
  static const _dorado = PdfColor.fromInt(0xFFC99A2E);
  static const _gris = PdfColors.grey700;

  static String _nombre(InformeArea i) =>
      'Informe ${i.area.titulo} ${i.rango.titulo}${i.busqueda.isEmpty ? '' : ' - ${i.busqueda}'}';

  /// Período y, si se filtró, con qué texto (lo impreso es solo eso).
  static String _subtitulo(InformeArea i) => '${i.rango.periodo.etiqueta}: ${i.rango.titulo}'
      '${i.busqueda.isEmpty ? '' : '   ·   Búsqueda: "${i.busqueda}"'}';

  // ------------------------------------------------------------------ PDF

  static Future<Uint8List> pdf(InformeArea i, {required String responsable}) async {
    final doc = pw.Document();
    final logo = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    const suave = pw.TextStyle(fontSize: 8, color: _gris);
    final colores = [_verde, _dorado, PdfColors.blueGrey400, PdfColors.red300];

    final maximo = i.series.expand((s) => s.valores).fold<double>(0, (m, v) => v > m ? v : m);

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Center(child: pw.Opacity(opacity: 0.06, child: pw.Image(logo, width: 360))),
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: suave),
      ),
      build: (context) => [
        pw.Row(children: [
          pw.Image(logo, width: 48, height: 48),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('INFORME · ${i.area.titulo.toUpperCase()}',
                  style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _verde)),
              pw.Text(_subtitulo(i),
                  style: const pw.TextStyle(fontSize: 10, color: _gris)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Emitido: ${fmtFechaHora(DateTime.now())}', style: suave),
            pw.Text('Por: $responsable', style: suave),
          ]),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(color: _verde, thickness: 1.6),
        pw.SizedBox(height: 8),

        // KPIs
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in i.kpis)
            pw.Container(
              width: 120,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: k.alerta ? PdfColors.red : PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(k.etiqueta, style: suave),
                pw.SizedBox(height: 2),
                pw.Text(k.valor,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: k.alerta ? PdfColors.red : PdfColors.black)),
              ]),
            ),
        ]),
        pw.SizedBox(height: 14),

        // Gráfico
        pw.Text(i.tituloGrafico, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _verde)),
        pw.SizedBox(height: 6),
        if (maximo <= 0)
          pw.Text('Sin datos en este período.', style: suave)
        else
          pw.SizedBox(
            height: 190,
            child: pw.Chart(
              grid: pw.CartesianGrid(
                xAxis: pw.FixedAxis.fromStrings(i.rango.etiquetas,
                    marginStart: 24, marginEnd: 24, ticks: true, textStyle: suave),
                yAxis: pw.FixedAxis(_marcas(maximo), divisions: true, textStyle: suave,
                    format: (v) => fmtNum(v, decimales: 0)),
              ),
              datasets: [
                for (var s = 0; s < i.series.length; s++)
                  pw.BarDataSet(
                    color: colores[s % colores.length],
                    legend: i.series[s].nombre,
                    width: _anchoBarra(i),
                    offset: (s - (i.series.length - 1) / 2) * (_anchoBarra(i) + 1),
                    data: [
                      for (var b = 0; b < i.series[s].valores.length; b++)
                        pw.PointChartValue(b.toDouble(), i.series[s].valores[b]),
                    ],
                  ),
              ],
            ),
          ),
        if (i.series.length > 1)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Wrap(spacing: 12, children: [
              for (var s = 0; s < i.series.length; s++)
                pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                  pw.Container(width: 8, height: 8, color: colores[s % colores.length]),
                  pw.SizedBox(width: 4),
                  pw.Text(i.series[s].nombre, style: suave),
                ]),
            ]),
          ),
        if (i.tieneProyeccion) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            'Proyección al cierre del período (al ritmo promedio por día de lo que va): '
            '${i.series.map((s) => '${s.nombre} ${fmtNum(s.totalProyectado, decimales: 0)} '
                '(van ${fmtNum(s.total, decimales: 0)})').join(' · ')}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
        if (i.anteriores != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Comparado con ${i.tituloAnterior}'
            '${i.barrasHastaHoy != null ? ' (hasta ${i.rango.etiquetas[i.barrasVisibles - 1]})' : ''}: '
            '${[
              for (var s = 0; s < i.series.length && s < i.anteriores!.length; s++)
                '${i.series[s].nombre} ${fmtNum(InformeArea.sumaHasta(i.series[s], i.barrasVisibles), decimales: 0)}'
                    ' (antes ${fmtNum(InformeArea.sumaHasta(i.anteriores![s], i.barrasVisibles), decimales: 0)})'
            ].join(' · ')}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
        pw.SizedBox(height: 14),

        // Tabla
        pw.Text(i.tituloTabla, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _verde)),
        pw.SizedBox(height: 6),
        if (i.filas.isEmpty)
          pw.Text('Sin datos en este período.', style: suave)
        else
          pw.TableHelper.fromTextArray(
            headers: i.columnas,
            data: i.filas,
            headerDecoration: const pw.BoxDecoration(color: _verde),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 9),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            cellAlignments: {for (var c = 1; c < i.columnas.length; c++) c: pw.Alignment.centerRight},
          ),
        if (i.nota != null) ...[
          pw.SizedBox(height: 8),
          pw.Text(i.nota!, style: suave),
        ],
      ],
    ));
    return doc.save();
  }

  /// Más angostas cuantas más barras (un año o un rango de 31 días).
  static double _anchoBarra(InformeArea i) {
    final n = i.rango.etiquetas.length * i.series.length;
    return n > 24 ? 5 : n > 12 ? 9 : 14;
  }

  /// Marcas "redondas" del eje Y hasta un poco más que el máximo.
  static List<double> _marcas(double maximo) {
    final paso = _pasoRedondo(maximo / 4);
    return [for (var v = 0.0; v <= maximo + paso; v += paso) v];
  }

  static double _pasoRedondo(double x) {
    if (x <= 0) return 1;
    var base = 1.0;
    while (base * 10 <= x) {
      base *= 10;
    }
    while (base > x) {
      base /= 10;
    }
    for (final m in [1, 2, 5, 10]) {
      if (base * m >= x) return base * m;
    }
    return base * 10;
  }

  static Future<String> guardarPdf(Uint8List bytes, InformeArea i) => ArchivoService.guardar(bytes,
      nombre: _nombre(i), ext: 'pdf', mimeType: 'application/pdf');

  // ---------------------------------------------------------------- Excel

  static Uint8List excel(InformeArea i, {required String responsable}) {
    final libro = xls.Excel.createExcel();
    libro.rename('Sheet1', 'Informe');
    final h = libro['Informe'];
    final titulo = xls.CellStyle(
        bold: true, fontSize: 14, fontColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'));
    final cabecera = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'),
    );
    final negrita = xls.CellStyle(bold: true);
    var fila = 0;

    void celda(int col, Object? v, [xls.CellStyle? estilo]) {
      final valor = v is num ? xls.DoubleCellValue(v.toDouble()) : xls.TextCellValue('${v ?? ''}');
      h.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila), valor,
          cellStyle: estilo);
    }

    celda(0, 'Informe · ${i.area.titulo}', titulo);
    fila++;
    celda(0, _subtitulo(i));
    fila++;
    celda(0, 'Emitido: ${fmtFechaHora(DateTime.now())} · Por: $responsable');
    fila += 2;

    celda(0, 'Indicadores', negrita);
    fila++;
    for (final k in i.kpis) {
      celda(0, k.etiqueta);
      celda(1, k.valor);
      if (k.alerta) celda(2, 'ALERTA');
      fila++;
    }
    fila++;

    // Una columna por serie: los números quedan como números, para que se
    // puedan graficar o sumar en Excel.
    celda(0, i.tituloGrafico, negrita);
    fila++;
    // Cada serie lleva al lado su columna de estimado (si hay proyección) y la
    // del período anterior (si se está comparando).
    final ant = i.anteriores;
    final colEst = i.tieneProyeccion ? 1 : 0;
    final cols = 1 + colEst + (ant != null ? 1 : 0);
    celda(0, i.rango.unidadBarra, cabecera);
    for (var s = 0; s < i.series.length; s++) {
      celda(s * cols + 1, i.series[s].nombre, cabecera);
      if (i.tieneProyeccion) celda(s * cols + 2, '${i.series[s].nombre} (estimado)', cabecera);
      if (ant != null) {
        celda(s * cols + 2 + colEst, '${i.series[s].nombre} (${i.tituloAnterior})', cabecera);
      }
    }
    fila++;
    for (var b = 0; b < i.rango.etiquetas.length; b++) {
      celda(0, i.rango.etiquetas[b]);
      for (var s = 0; s < i.series.length; s++) {
        celda(s * cols + 1, i.series[s].valores[b]);
        if (i.tieneProyeccion) celda(s * cols + 2, i.series[s].proyeccion![b].roundToDouble());
        if (ant != null && s < ant.length) celda(s * cols + 2 + colEst, ant[s].valores[b]);
      }
      fila++;
    }
    if (i.tieneProyeccion) {
      celda(0, 'Proyección al cierre', negrita);
      for (var s = 0; s < i.series.length; s++) {
        celda(s * cols + 1, i.series[s].totalProyectado!.roundToDouble(), negrita);
      }
      fila++;
    }
    fila++;

    celda(0, i.tituloTabla, negrita);
    fila++;
    for (var c = 0; c < i.columnas.length; c++) {
      celda(c, i.columnas[c], cabecera);
    }
    fila++;
    for (final f in i.filas) {
      for (var c = 0; c < f.length; c++) {
        celda(c, f[c]);
      }
      fila++;
    }
    if (i.nota != null) {
      fila++;
      celda(0, i.nota);
    }

    h.setColumnWidth(0, 34);
    for (var c = 1; c < 6; c++) {
      h.setColumnWidth(c, 16);
    }
    return Uint8List.fromList(libro.save() ?? []);
  }

  static Future<String> guardarExcel(Uint8List bytes, InformeArea i) => ArchivoService.guardar(bytes,
      nombre: _nombre(i),
      ext: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
