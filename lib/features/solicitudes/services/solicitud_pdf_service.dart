import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/archivo_service.dart';
import '../../../utils/formatters.dart';
import '../models/solicitud.dart';

/// Constancia en PDF de una solicitud a Gerencia YA RESUELTA (aprobada o
/// rechazada, con el motivo), para imprimir y firmar si se quiere — es
/// opcional (mismo lenguaje visual que los reportes de inventario: logo,
/// verde de marca, encabezado con fecha de emisión).
class SolicitudPdfService {
  static Future<Uint8List> pdf(Solicitud s) async {
    final doc = pw.Document();
    const verde = PdfColor.fromInt(0xFF1B5E3A);
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
                  pw.Text('CONSTANCIA DE SOLICITUD',
                      style:
                          pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: verde)),
                  pw.Text('Salvietti Control · N° de solicitud ${s.id}',
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
          fila('Fecha de solicitud', fmtFechaHora(s.fecha)),
          fila('Solicitante', s.solicitanteNombre ?? '—'),
          fila('Tipo', TipoSolicitud.etiqueta(s.tipo)),
          fila('Asunto', s.asunto),
          if (s.itemDetalle != null)
            fila('Ítem', '${s.itemDetalle}'
                '${s.cantidadSugerida == null ? '' : ' (${fmtNum(s.cantidadSugerida)} ${s.itemUnidad ?? ''})'}'),
          if (s.detalle != null) fila('Detalle', s.detalle!),
          pw.SizedBox(height: 10),
          // Lo que resolvió Gerencia, bien visible: la constancia sirve tanto
          // para una aprobación como para dejar registrado un rechazo.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _colorEstado(s.estado), width: 1.4),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(s.estado.etiqueta.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold, color: _colorEstado(s.estado))),
              if (s.resueltaEn != null) ...[
                pw.SizedBox(height: 4),
                fila('Resuelta por', s.resueltaPorNombre ?? '—'),
                fila('Fecha de resolución', fmtFechaHora(s.resueltaEn)),
                if (s.respuesta != null)
                  fila(s.estado == EstadoSolicitud.rechazada ? 'Motivo del rechazo' : 'Respuesta',
                      s.respuesta!),
              ],
            ]),
          ),
          pw.SizedBox(height: 60),
          pw.Row(children: [
            pw.Expanded(
              child: pw.Column(children: [
                pw.Container(height: 1, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Text('Firma del solicitante', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.SizedBox(width: 40),
            pw.Expanded(
              child: pw.Column(children: [
                pw.Container(height: 1, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Text('Firma de Gerencia', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          ]),
        ],
      ),
    ));

    return doc.save();
  }

  static PdfColor _colorEstado(EstadoSolicitud e) => switch (e) {
        EstadoSolicitud.aprobada => const PdfColor.fromInt(0xFF16A34A),
        EstadoSolicitud.rechazada => const PdfColor.fromInt(0xFFDC2626),
        EstadoSolicitud.pendiente => const PdfColor.fromInt(0xFFD97706),
      };

  static Future<String> guardar(Uint8List bytes, Solicitud s) => ArchivoService.guardar(
        bytes,
        nombre: 'Solicitud ${s.id} - ${s.asunto}',
        ext: 'pdf',
        mimeType: 'application/pdf',
      );
}
