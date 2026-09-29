import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/insumo.dart';
import '../models/movimiento.dart';
import '../utils/formatters.dart';
import 'archivo_service.dart';

const _etiquetaTipo = {
  'ingreso': 'Entrada',
  'salida': 'Salida',
  'ajuste': 'Ajuste',
  'produccion': 'Producción',
};

/// Genera y guarda los reportes de movimientos (PDF y Excel).
///
/// Metodología (igual que el sistema de reclamos de referencia): el reporte
/// contiene EXACTAMENTE lo que se está mostrando según los filtros
/// (buscador + Desde/Hasta); sin filtros sale el listado general. Además,
/// cada ítem tiene su propia ficha individual ([ficha]).
///
/// El PDF replica el formato de ese reporte (hoja apaisada, logo, título
/// centrado, emisión y rango de fechas, responsable, tabla numerada con
/// encabezado de color, marca de agua y paginado) con los colores de
/// Salvietti. mPDF es una librería PHP y no se puede usar desde esta app
/// Flutter, así que se arma con el paquete `pdf` de Dart.
class ReporteService {
  static String _fecha(DateTime? f) => f == null ? '__/__/____' : fmtFecha(f);

  static Future<Uint8List> pdf({
    required String titulo,
    required String subtitulo,
    required DateTime? desde,
    required DateTime? hasta,
    required String responsable,
    required List<Movimiento> movimientos,
    required Map<String, Insumo> insumoPorId,
    List<MapEntry<String, String>> ficha = const [],
  }) async {
    final doc = pw.Document();
    final verde = PdfColor.fromInt(0xFF1B5E3A);
    final logo = pw.MemoryImage(
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List());

    String nombre(String id) => insumoPorId[id]?.detalle ?? id;
    String codigo(String id) => insumoPorId[id]?.codigo ?? '-';

    final ordenados = [...movimientos]
      ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    int contar(String tipo) => ordenados.where((m) => m.tipo == tipo).length;

    final filas = <List<String>>[
      for (final (i, m) in ordenados.indexed)
        [
          '${i + 1}',
          codigo(m.itemId),
          nombre(m.itemId),
          fmtFechaHora(m.creadoEn),
          _etiquetaTipo[m.tipo] ?? m.tipo,
          fmtNum(m.cantidad, decimales: 0),
          m.unidadMedida ?? '',
          m.lote ?? '',
          m.proveedor ?? '',
          m.nFactura ?? '',
          m.observacion ?? '',
        ],
    ];

    const estiloSuave = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        // Marca de agua: el logo, muy tenue, centrado en cada hoja.
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Center(
            child: pw.Opacity(opacity: 0.07, child: pw.Image(logo, width: 380)),
          ),
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
            style: estiloSuave),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(logo, width: 52, height: 52),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(titulo.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: verde)),
                  pw.SizedBox(height: 2),
                  pw.Text(subtitulo,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Fecha de emisión: ${fmtFechaHora(DateTime.now())}',
                    style: estiloSuave),
                pw.Text('Desde: ${_fecha(desde)}', style: estiloSuave),
                pw.Text('Hasta: ${_fecha(hasta)}', style: estiloSuave),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: verde, thickness: 1.6),
        pw.SizedBox(height: 6),
        pw.Container(
          decoration:
              pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
          child: pw.Row(children: [
            pw.Container(
              width: 110,
              padding: const pw.EdgeInsets.all(6),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(right: pw.BorderSide(color: PdfColors.grey400))),
              child: pw.Text('RESPONSABLE:',
                  style:
                      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(responsable, style: const pw.TextStyle(fontSize: 10)),
            ),
          ]),
        ),
        if (ficha.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  color: PdfColor.fromInt(0xFFE3F1E8),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text('INFORMACIÓN DEL INSUMO',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: verde)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Wrap(
                    spacing: 26,
                    runSpacing: 8,
                    children: [
                      for (final e in ficha)
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(e.key, style: estiloSuave),
                            pw.Text(e.value,
                                style: pw.TextStyle(
                                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const [
            'N°',
            'Código',
            'Insumo',
            'Fecha',
            'Tipo',
            'Cantidad',
            'Unidad',
            'Lote',
            'Proveedor',
            'N° Factura',
            'Observación',
          ],
          data: filas,
          headerDecoration: pw.BoxDecoration(color: verde),
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
          cellStyle: const pw.TextStyle(fontSize: 8),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          cellAlignments: {
            0: pw.Alignment.center,
            5: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(0.5),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(2.6),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(1),
            6: const pw.FlexColumnWidth(0.8),
            7: const pw.FlexColumnWidth(1),
            8: const pw.FlexColumnWidth(1.6),
            9: const pw.FlexColumnWidth(1.1),
            10: const pw.FlexColumnWidth(2.2),
          },
        ),
        pw.SizedBox(height: 8),
        pw.Text(
            'Total de movimientos: ${ordenados.length}   ·   '
            'Entradas: ${contar('ingreso')}   ·   Salidas: ${contar('salida')}   ·   '
            'Ajustes: ${contar('ajuste')}   ·   Producción: ${contar('produccion')}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    ));
    return doc.save();
  }

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String _fechasNombre(DateTime? desde, DateTime? hasta) {
    if (desde == null && hasta == null) return _iso(DateTime.now());
    if (desde != null && hasta != null) return '${_iso(desde)} a ${_iso(hasta)}';
    return desde != null ? 'desde ${_iso(desde)}' : 'hasta ${_iso(hasta!)}';
  }

  /// Nombre de un reporte general: qué lista es + fecha(s).
  /// Ej.: "Listado de movimientos Tapas 2026-09-19".
  static String nombreListado(String lista, DateTime? desde, DateTime? hasta) =>
      'Listado de movimientos $lista ${_fechasNombre(desde, hasta)}';

  /// Nombre del reporte de UN ítem: código + nombre + fecha(s).
  /// Ej.: "MP-001 Esencia de limón 2026-09-01 a 2026-09-19".
  static String nombreIndividual(
          String codigo, String detalle, DateTime? desde, DateTime? hasta) =>
      '$codigo $detalle ${_fechasNombre(desde, hasta)}';

  static Uint8List excel({
    required String titulo,
    required String subtitulo,
    required DateTime? desde,
    required DateTime? hasta,
    required String responsable,
    required List<Movimiento> movimientos,
    required Map<String, Insumo> insumoPorId,
    List<MapEntry<String, String>> ficha = const [],
  }) {
    const columnas = [
      'N°',
      'CÓDIGO',
      'INSUMO',
      'FECHA',
      'TIPO',
      'CANTIDAD',
      'UNIDAD',
      'LOTE',
      'PROVEEDOR',
      'N° FACTURA',
      'OBSERVACIÓN',
    ];
    const anchos = [6.0, 12.0, 34.0, 18.0, 12.0, 12.0, 9.0, 14.0, 26.0, 14.0, 40.0];
    final ultima = columnas.length - 1;

    xls.ExcelColor color(String hex) => xls.ExcelColor.fromHexString(hex);
    final verde = color('#FF1B5E3A');
    final negro = color('#FF0E1512');
    final blanco = color('#FFFFFFFF');

    final ordenados = [...movimientos]
      ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    int contar(String tipo) => ordenados.where((m) => m.tipo == tipo).length;

    final libro = xls.Excel.createExcel();
    libro.rename('Sheet1', 'Movimientos');
    final hoja = libro['Movimientos'];
    for (var c = 0; c < anchos.length; c++) {
      hoja.setColumnWidth(c, anchos[c]);
    }

    xls.CellIndex celda(int c, int r) =>
        xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

    // Escribe una fila de texto que ocupa todo el ancho (celdas combinadas).
    var fila = 0;
    void bandaCompleta(String texto, xls.CellStyle estilo, {double? alto}) {
      hoja.merge(celda(0, fila), celda(ultima, fila),
          customValue: xls.TextCellValue(texto));
      hoja.cell(celda(0, fila)).cellStyle = estilo;
      if (alto != null) hoja.setRowHeight(fila, alto);
      fila++;
    }

    bandaCompleta(
      'SALVIETTI',
      xls.CellStyle(
        bold: true,
        fontSize: 22,
        fontColorHex: blanco,
        backgroundColorHex: verde,
        horizontalAlign: xls.HorizontalAlign.Center,
        verticalAlign: xls.VerticalAlign.Center,
      ),
      alto: 38,
    );
    bandaCompleta(
      titulo.toUpperCase(),
      xls.CellStyle(
        bold: true,
        fontSize: 13,
        fontColorHex: verde,
        horizontalAlign: xls.HorizontalAlign.Center,
      ),
      alto: 22,
    );
    if (subtitulo.isNotEmpty) {
      bandaCompleta(
        subtitulo,
        xls.CellStyle(
          fontSize: 10,
          fontColorHex: color('#FF555555'),
          horizontalAlign: xls.HorizontalAlign.Center,
        ),
      );
    }
    bandaCompleta(
      'Fecha de emisión: ${fmtFechaHora(DateTime.now())}   ·   '
      'Desde: ${_fecha(desde)}   ·   Hasta: ${_fecha(hasta)}   ·   '
      'Responsable: $responsable',
      xls.CellStyle(
        fontSize: 10,
        fontColorHex: color('#FF555555'),
        horizontalAlign: xls.HorizontalAlign.Center,
      ),
    );

    if (ficha.isNotEmpty) {
      fila++;
      for (final e in ficha) {
        hoja.merge(celda(0, fila), celda(2, fila),
            customValue: xls.TextCellValue(e.key));
        hoja.cell(celda(0, fila)).cellStyle = xls.CellStyle(
            bold: true, backgroundColorHex: color('#FFE3F1E8'), fontColorHex: verde);
        hoja.merge(celda(3, fila), celda(ultima, fila),
            customValue: xls.TextCellValue(e.value));
        fila++;
      }
    }
    fila++;

    // Encabezado de la tabla.
    final estiloEncabezado = xls.CellStyle(
      bold: true,
      fontColorHex: blanco,
      backgroundColorHex: verde,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
    );
    for (var c = 0; c < columnas.length; c++) {
      hoja.updateCell(celda(c, fila), xls.TextCellValue(columnas[c]),
          cellStyle: estiloEncabezado);
    }
    hoja.setRowHeight(fila, 24);
    fila++;

    // Filas de datos, con color alterno.
    for (final (i, m) in ordenados.indexed) {
      final fondo = i.isEven ? color('#FFFFFFFF') : color('#FFF1F6F3');
      xls.CellStyle e({xls.HorizontalAlign? h}) => xls.CellStyle(
          backgroundColorHex: fondo,
          horizontalAlign: h ?? xls.HorizontalAlign.Left);
      final valores = <xls.CellValue>[
        xls.IntCellValue(i + 1),
        xls.TextCellValue(insumoPorId[m.itemId]?.codigo ?? '-'),
        xls.TextCellValue(insumoPorId[m.itemId]?.detalle ?? m.itemId),
        xls.TextCellValue(fmtFechaHora(m.creadoEn)),
        xls.TextCellValue(_etiquetaTipo[m.tipo] ?? m.tipo),
        xls.DoubleCellValue(m.cantidad),
        xls.TextCellValue(m.unidadMedida ?? ''),
        xls.TextCellValue(m.lote ?? ''),
        xls.TextCellValue(m.proveedor ?? ''),
        xls.TextCellValue(m.nFactura ?? ''),
        xls.TextCellValue(m.observacion ?? ''),
      ];
      for (var c = 0; c < valores.length; c++) {
        hoja.updateCell(celda(c, fila), valores[c],
            cellStyle: e(
                h: (c == 0)
                    ? xls.HorizontalAlign.Center
                    : (c == 5 ? xls.HorizontalAlign.Right : null)));
      }
      fila++;
    }

    // Fila de total, como "TOTAL DE REGISTROS ..." del listado de referencia.
    final estiloTotal = xls.CellStyle(
      bold: true,
      fontColorHex: blanco,
      backgroundColorHex: negro,
    );
    hoja.merge(celda(0, fila), celda(ultima - 1, fila),
        customValue: xls.TextCellValue('TOTAL DE MOVIMIENTOS'));
    hoja.cell(celda(0, fila)).cellStyle = estiloTotal;
    hoja.updateCell(celda(ultima, fila), xls.IntCellValue(ordenados.length),
        cellStyle: xls.CellStyle(
            bold: true,
            fontColorHex: blanco,
            backgroundColorHex: negro,
            horizontalAlign: xls.HorizontalAlign.Right));
    fila++;
    bandaCompleta(
      'Entradas: ${contar('ingreso')}   ·   Salidas: ${contar('salida')}   ·   '
      'Ajustes: ${contar('ajuste')}   ·   Producción: ${contar('produccion')}',
      xls.CellStyle(
        italic: true,
        fontSize: 10,
        fontColorHex: color('#FF555555'),
        horizontalAlign: xls.HorizontalAlign.Right,
      ),
    );

    return Uint8List.fromList(libro.save() ?? []);
  }

  /// Guarda el reporte sin sobrescribir (ver [ArchivoService]) y devuelve
  /// el mensaje con dónde quedó.
  static Future<String> guardar(
    Uint8List bytes, {
    required bool esPdf,
    required String nombre,
  }) =>
      ArchivoService.guardar(
        bytes,
        nombre: nombre,
        ext: esPdf ? 'pdf' : 'xlsx',
        mimeType: esPdf
            ? 'application/pdf'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
}
