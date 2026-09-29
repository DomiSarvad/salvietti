import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/archivo_service.dart';
import '../../../utils/formatters.dart';
import '../models/soda_modelos.dart';

/// Constancia en PDF de una entrega de Soda Cáustica (producto peligroso:
/// siempre lleva constancia para firmar). Mismo lenguaje visual que la
/// constancia de Solicitudes.
class SodaPdfService {
  static Future<Uint8List> pdf(EntregaSoda e) async {
    final doc = pw.Document();
    final verde = PdfColor.fromInt(0xFF1B5E3A);
    final logo =
        pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());

    pw.Widget fila(String etiqueta, String valor) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                  width: 130,
                  child: pw.Text(etiqueta,
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(child: pw.Text(valor, style: const pw.TextStyle(fontSize: 10))),
            ],
          ),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Image(logo, width: 48, height: 48),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CONSTANCIA DE ENTREGA — PRODUCTO PELIGROSO',
                      style:
                          pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: verde)),
                  pw.Text('Salvietti Control · Soda Cáustica · N° ${e.id}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Text('Emitido: ${fmtFechaHora(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ]),
          pw.SizedBox(height: 8),
          pw.Divider(color: verde, thickness: 1.4),
          pw.SizedBox(height: 8),
          fila('Fecha y hora', fmtFechaHora(e.fechaHora)),
          fila('Producto', '${e.codigo} · ${e.detalle}'),
          fila('Cantidad', '${fmtNum(e.cantidad)} ${e.unidad}'),
          fila('Entregado a', e.entregadoA),
          if (e.areaRecibe != null) fila('Área', e.areaRecibe!),
          if (e.motivo != null) fila('Motivo o uso', e.motivo!),
          if (e.saldoRestante != null)
            fila('Saldo restante', '${fmtNum(e.saldoRestante)} ${e.unidad}'),
          fila('Entregado por', e.responsableNombre ?? '—'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.red400),
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text(
                'Manipular con guantes y protección ocular. No mezclar con otros productos '
                'químicos. En caso de contacto con la piel, lavar de inmediato con abundante agua.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red900)),
          ),
          pw.SizedBox(height: 60),
          pw.Row(children: [
            pw.Expanded(
              child: pw.Column(children: [
                pw.Container(height: 1, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Text('Firma de quien recibe', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.SizedBox(width: 40),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Container(height: 1, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Text('Firma del encargado de Soda Cáustica',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          ]),
        ],
      ),
    ));

    return doc.save();
  }

  static Future<String> guardar(Uint8List bytes, EntregaSoda e) => ArchivoService.guardar(
        bytes,
        nombre: 'Entrega soda caustica ${e.id} - ${e.entregadoA}',
        ext: 'pdf',
        mimeType: 'application/pdf',
      );
}
