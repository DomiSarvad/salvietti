import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../shared/reportes/comprobante_pdf.dart';
import '../../../utils/formatters.dart';
import '../models/entregas_modelos.dart';

/// Detalle de un pedido de un área a Almacén, con su comprobante en PDF
/// (qué se pidió, qué se entregó, qué recibió el área y qué se devolvió).
Future<void> abrirDetallePedido(BuildContext context, Pedido p, Color colorEstado) {
  String cant(double? v, String u) => v == null ? '—' : '${fmtNum(v)} $u';
  return PaginaDetalle.abrir(
    context,
    PaginaDetalle(
      titulo: 'Pedido #${p.id} · ${AreaPedido.etiqueta(p.areaDestino)}',
      subtitulo: 'Pedido a Almacén',
      estado: p.estado.etiqueta,
      colorEstado: colorEstado,
      nombrePdf: 'Pedido ${p.id} - ${AreaPedido.etiqueta(p.areaDestino)}',
      firmasPdf: const ['Entregó (Almacén)', 'Recibió (área)'],
      secciones: [
        SeccionDetalle(titulo: 'Pedido', filas: [
          ('Área', AreaPedido.etiqueta(p.areaDestino)),
          ('Sale de', p.almacenOrigen),
          ('Pedido por', p.solicitanteNombre),
          ('Fecha', fmtFechaHora(p.fecha)),
          ('Motivo', p.motivo),
        ]),
        SeccionDetalle(titulo: 'Entrega', filas: [
          ('Entregado por', p.entregadoPorNombre),
          ('Entregado el', p.entregadoEn == null ? null : fmtFechaHora(p.entregadoEn)),
        ]),
        SeccionDetalle(titulo: 'Recepción del área', filas: [
          ('Confirmado por', p.confirmadoPorNombre),
          ('Confirmado el', p.confirmadoEn == null ? null : fmtFechaHora(p.confirmadoEn)),
          ('Nota', p.notaConformidad),
          ('Resolución', p.resolucion),
        ]),
      ],
      tablasPdf: [
        TablaComprobante(
          titulo: 'Ítems',
          encabezados: const ['Código', 'Ítem', 'Pedido', 'Entregado', 'Recibido', 'Devuelto', 'Observación'],
          filas: [
            for (final l in p.lineas)
              [
                l.codigo,
                l.detalle,
                cant(l.cantidadPedida, l.unidad),
                cant(l.cantidadEntregada, l.unidad),
                cant(l.cantidadRecibida, l.unidad),
                l.cantidadDevuelta > 0 ? cant(l.cantidadDevuelta, l.unidad) : '—',
                l.observacion ?? '',
              ]
          ],
        ),
      ],
      extra: [
        SeccionDetalle(titulo: 'Ítems', filas: [
          for (final l in p.lineas)
            (
              l.detalle,
              'Pedido ${cant(l.cantidadPedida, l.unidad)}'
                  '${l.cantidadEntregada == null ? '' : ' · entregado ${cant(l.cantidadEntregada, l.unidad)}'}'
                  '${l.cantidadRecibida == null ? '' : ' · recibido ${cant(l.cantidadRecibida, l.unidad)}'}'
                  '${l.cantidadDevuelta > 0 ? ' · devuelto ${cant(l.cantidadDevuelta, l.unidad)}' : ''}'
                  '${l.observacion == null ? '' : '\n${l.observacion}'}'
            ),
        ]),
      ],
    ),
  );
}
