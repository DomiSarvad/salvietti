import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/soda_modelos.dart';

/// Detalle de una entrega de Soda Cáustica, con su constancia en PDF.
Future<void> abrirDetalleSoda(BuildContext context, EntregaSoda e, VoidCallback onPdf) =>
    PaginaDetalle.abrir(
      context,
      PaginaDetalle(
        titulo: '${e.detalle} · ${fmtNum(e.cantidad)} ${e.unidad}',
        subtitulo: 'Soda Cáustica · ${fmtFechaHora(e.fechaHora)}',
        secciones: [
          SeccionDetalle(titulo: 'Entrega', filas: [
            ('Producto', '${e.codigo} · ${e.detalle}'),
            ('Cantidad', '${fmtNum(e.cantidad)} ${e.unidad}'),
            ('Entregado a', e.entregadoA),
            ('Área que recibe', e.areaRecibe),
            ('Motivo', e.motivo),
          ]),
          SeccionDetalle(filas: [
            ('Saldo restante', e.saldoRestante == null ? null : '${fmtNum(e.saldoRestante)} ${e.unidad}'),
            ('Entregó', e.responsableNombre),
          ]),
        ],
        extra: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primario),
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626)),
            label: const Text('Constancia en PDF'),
          ),
        ],
      ),
    );
