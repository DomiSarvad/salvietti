import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/archivo_service.dart';
import '../../../utils/formatters.dart';

/// Una fila lista para el reporte: ya con la ubicación y el estado resueltos
/// (`InventarioService.textoRutaRelativa`/`situacion` los calcula, así este
/// servicio no necesita conocer al service ni sus modelos).
class FilaReporteInventario {
  final String codigo;
  final String detalle;
  final String ubicacion;
  final double cantidadSistema;
  final String unidad;
  final double? stockMinimo;
  final double? diasExistencia;
  final String estado;
  const FilaReporteInventario({
    required this.codigo,
    required this.detalle,
    required this.ubicacion,
    required this.cantidadSistema,
    required this.unidad,
    required this.stockMinimo,
    required this.diasExistencia,
    required this.estado,
  });
}

/// Reporte imprimible del inventario de un almacén, con EXACTAMENTE lo que
/// se está viendo en pantalla: respeta el almacén, la categoría y lo escrito
/// en el buscador (o el filtro "Pedido") — mismo criterio que
/// `ReporteService` (legacy) para los movimientos: el reporte es un espejo
/// de la pantalla, no un listado aparte.
class InventarioPdfService {
  static Future<Uint8List> reporte({
    required String almacenNombre,
    required String? categoriaTexto,
    required String busqueda,
    required bool soloPedido,
    required String responsable,
    required List<FilaReporteInventario> filas,
  }) async {
    final doc = pw.Document();
    final verde = PdfColor.fromInt(0xFF1B5E3A);
    final logo =
        pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());

    final filtros = <String>[
      'Almacén: $almacenNombre',
      if (categoriaTexto != null) 'Categoría: $categoriaTexto',
      if (busqueda.trim().isNotEmpty) 'Búsqueda: "${busqueda.trim()}"',
      if (soloPedido) 'Solo ítems a pedir',
    ].join('   ·   ');

    final ordenadas = [...filas]..sort((a, b) => a.detalle.compareTo(b.detalle));
    final datos = [
      for (final f in ordenadas)
        [
          f.codigo,
          f.detalle,
          f.ubicacion,
          '${fmtNum(f.cantidadSistema)} ${f.unidad}',
          f.stockMinimo == null ? '—' : fmtNum(f.stockMinimo),
          f.diasExistencia == null ? '—' : fmtNum(f.diasExistencia, decimales: 1),
          f.estado,
        ],
    ];

    const estiloSuave = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
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
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('REPORTE DE INVENTARIO',
                      style: pw.TextStyle(
                          fontSize: 18, fontWeight: pw.FontWeight.bold, color: verde)),
                  pw.SizedBox(height: 2),
                  pw.Text(filtros, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Emitido: ${fmtFechaHora(DateTime.now())}', style: estiloSuave),
                pw.Text('Responsable: $responsable', style: estiloSuave),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: verde, thickness: 1.6),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: const ['Código', 'Detalle', 'Ubicación', 'Stock', 'Mínimo', 'Días', 'Estado'],
          data: datos,
          headerDecoration: pw.BoxDecoration(color: verde),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
          cellStyle: const pw.TextStyle(fontSize: 9),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          border: pw.TableBorder.all(color: PdfColors.grey300),
          cellAlignments: {
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FlexColumnWidth(2.2),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(0.8),
            6: const pw.FlexColumnWidth(1.1),
          },
        ),
        pw.SizedBox(height: 8),
        pw.Text('Total de ítems: ${ordenadas.length}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    ));
    return doc.save();
  }

  static Future<String> guardar(Uint8List bytes, String almacenNombre) => ArchivoService.guardar(
        bytes,
        nombre: 'Inventario $almacenNombre ${fmtFecha(DateTime.now())}',
        ext: 'pdf',
        mimeType: 'application/pdf',
      );
}
