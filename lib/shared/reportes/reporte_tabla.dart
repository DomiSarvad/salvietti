import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/archivo_service.dart';
import '../../utils/formatters.dart';

/// Un reporte en forma de tabla: lo que muestra una lista (ya filtrada) con
/// sus columnas. Lo arman los services; [ReporteTablaExport] lo convierte en
/// PDF o Excel con el estilo de la marca.
///
/// Cada celda lleva el VALOR, no el texto: un número va como `num` (en el PDF
/// se ve "1.234,5"; en Excel queda como número, para sumar o graficar), una
/// fecha como `DateTime`, y lo que falta como `null` ("—").
class ReporteTabla {
  final String titulo;
  final String filtros; // ej. 'Búsqueda: "papaya" · Desde 01/10/2026'
  final List<String> columnas;
  final List<List<Object?>> filas;

  const ReporteTabla({
    required this.titulo,
    required this.filtros,
    required this.columnas,
    required this.filas,
  });

  bool get vacio => filas.isEmpty;

  /// Columnas que traen números (para alinearlas a la derecha).
  Set<int> get numericas => {
        for (var c = 0; c < columnas.length; c++)
          if (filas.any((f) => c < f.length && f[c] is num)) c
      };

  static String texto(Object? v) {
    if (v == null) return '—';
    if (v is int) return fmtNum(v, decimales: 0);
    if (v is double) return fmtNum(v, decimales: v == v.roundToDouble() ? 0 : 2);
    if (v is DateTime) {
      final l = v.toLocal();
      return (l.hour == 0 && l.minute == 0) ? fmtFecha(l) : fmtFechaHora(l);
    }
    return v.toString();
  }
}

class ReporteTablaExport {
  static const _verde = PdfColor.fromInt(0xFF1B5E3A);
  static const _gris = PdfColors.grey700;

  /// Apaisado si la tabla es ancha (más de 6 columnas).
  static Future<Uint8List> pdf(ReporteTabla r, {required String responsable}) async {
    final doc = pw.Document();
    final logo = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    const suave = pw.TextStyle(fontSize: 8, color: _gris);
    final apaisado = r.columnas.length > 6;

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: apaisado ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
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
              pw.Text(r.titulo.toUpperCase(),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _verde)),
              pw.SizedBox(height: 2),
              pw.Text(r.filtros, style: const pw.TextStyle(fontSize: 9, color: _gris)),
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
        if (r.vacio)
          pw.Text('No hay registros con estos filtros.', style: suave)
        else
          pw.TableHelper.fromTextArray(
            headers: r.columnas,
            data: [for (final f in r.filas) [for (final v in f) ReporteTabla.texto(v)]],
            headerDecoration: const pw.BoxDecoration(color: _verde),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            cellAlignments: {for (final c in r.numericas) c: pw.Alignment.centerRight},
          ),
        pw.SizedBox(height: 8),
        pw.Text('Total de registros: ${r.filas.length}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    ));
    return doc.save();
  }

  static Uint8List excel(ReporteTabla r, {required String responsable}) {
    final libro = xls.Excel.createExcel();
    libro.rename('Sheet1', 'Reporte');
    final h = libro['Reporte'];
    final cabecera = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A'),
    );
    void celda(int col, int fila, xls.CellValue v, [xls.CellStyle? e]) =>
        h.updateCell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila), v, cellStyle: e);

    celda(0, 0, xls.TextCellValue(r.titulo),
        xls.CellStyle(bold: true, fontSize: 14, fontColorHex: xls.ExcelColor.fromHexString('#FF1B5E3A')));
    celda(0, 1, xls.TextCellValue(r.filtros));
    celda(0, 2, xls.TextCellValue('Emitido: ${fmtFechaHora(DateTime.now())} · Por: $responsable'));
    const inicio = 4;
    for (var c = 0; c < r.columnas.length; c++) {
      celda(c, inicio, xls.TextCellValue(r.columnas[c]), cabecera);
      h.setColumnWidth(c, c == 0 ? 22 : 18);
    }
    for (var f = 0; f < r.filas.length; f++) {
      for (var c = 0; c < r.filas[f].length; c++) {
        final v = r.filas[f][c];
        celda(c, inicio + 1 + f,
            v is num ? xls.DoubleCellValue(v.toDouble()) : xls.TextCellValue(v == null ? '' : ReporteTabla.texto(v)));
      }
    }
    return Uint8List.fromList(libro.save() ?? []);
  }

  static String _nombre(ReporteTabla r) => '${r.titulo} ${fmtFecha(DateTime.now())}';

  static Future<String> guardarPdf(Uint8List b, ReporteTabla r) =>
      ArchivoService.guardar(b, nombre: _nombre(r), ext: 'pdf', mimeType: 'application/pdf');

  static Future<String> guardarExcel(Uint8List b, ReporteTabla r) => ArchivoService.guardar(b,
      nombre: _nombre(r),
      ext: 'xlsx',
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
