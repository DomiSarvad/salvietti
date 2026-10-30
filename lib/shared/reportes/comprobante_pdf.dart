import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/archivo_service.dart';
import '../../utils/formatters.dart';

/// Tabla de un comprobante (ítems de un pedido, movimientos de un ítem…).
class TablaComprobante {
  final String? titulo;
  final List<String> encabezados;
  final List<List<String>> filas;
  const TablaComprobante({this.titulo, required this.encabezados, required this.filas});
}

/// Comprobante en PDF de UN registro (pedido, pedido de compra, receta, ficha
/// de un ítem): mismo aspecto que la constancia de Solicitudes — logo, verde
/// de marca, estado en un recuadro de color, datos "etiqueta — valor", tabla
/// opcional y líneas de firma. Las filas sin valor no se imprimen.
class ComprobantePdf {
  static Future<Uint8List> generar({
    required String titulo,
    String? subtitulo,
    String? estado,
    int? colorEstado, // ARGB, el mismo de la pantalla
    List<(String?, List<(String, String?)>)> secciones = const [],
    List<TablaComprobante> tablas = const [],
    List<String> firmas = const [],
  }) async {
    final doc = pw.Document();
    const verde = PdfColor.fromInt(0xFF1B5E3A);
    final colorE = PdfColor.fromInt(colorEstado ?? 0xFF1B5E3A);
    final logo = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());

    pw.Widget fila(String etiqueta, String valor) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(
                width: 150,
                child: pw.Text(etiqueta,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(child: pw.Text(valor, style: const pw.TextStyle(fontSize: 10))),
          ]),
        );

    bool conValor((String, String?) f) => (f.$2 ?? '').trim().isNotEmpty && f.$2 != '-';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Página ${c.pageNumber} de ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (context) => [
        pw.Row(children: [
          pw.Image(logo, width: 48, height: 48),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(titulo.toUpperCase(),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: verde)),
              pw.Text('Salvietti Control${subtitulo == null ? '' : ' · $subtitulo'}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ]),
          ),
          pw.Text('Emitido: ${fmtFechaHora(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
        pw.SizedBox(height: 8),
        pw.Divider(color: verde, thickness: 1.4),
        pw.SizedBox(height: 6),
        if (estado != null)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: colorE, width: 1.4),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(estado.toUpperCase(),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: colorE)),
          ),
        for (final s in secciones)
          if (s.$2.any(conValor)) ...[
            if (s.$1 != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
                child: pw.Text(s.$1!,
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: verde)),
              ),
            for (final f in s.$2.where(conValor)) fila(f.$1, f.$2!),
          ],
        for (final t in tablas) ...[
          pw.SizedBox(height: 10),
          if (t.titulo != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(t.titulo!,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: verde)),
            ),
          if (t.filas.isEmpty)
            pw.Text('Sin registros.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: t.encabezados,
              data: t.filas,
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: verde),
              cellStyle: const pw.TextStyle(fontSize: 9),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F3)),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            ),
        ],
        if (firmas.isNotEmpty) ...[
          pw.SizedBox(height: 60),
          pw.Row(children: [
            for (var i = 0; i < firmas.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 40),
              pw.Expanded(
                child: pw.Column(children: [
                  pw.Container(height: 1, color: PdfColors.grey600),
                  pw.SizedBox(height: 4),
                  pw.Text(firmas[i], style: const pw.TextStyle(fontSize: 9)),
                ]),
              ),
            ],
          ]),
        ],
      ],
    ));
    return doc.save();
  }

  static Future<String> guardar(Uint8List bytes, String nombre) =>
      ArchivoService.guardar(bytes, nombre: nombre, ext: 'pdf', mimeType: 'application/pdf');
}
