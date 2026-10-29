import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/llenadora_modelos.dart';

/// Detalle de una corrida de Llenadora (tocar su tarjeta en el historial).
Future<void> abrirDetalleLlenadora(BuildContext context, CorridaLlenadora c) {
  final color = switch (c.estado) {
    EstadoCorrida.enCurso => const Color(0xFFD97706),
    EstadoCorrida.finalizada => const Color(0xFF16A34A),
    EstadoCorrida.anulada => Colors.black45,
  };
  String? n(num? v) => v == null || v == 0 ? null : fmtNum(v, decimales: 0);
  return PaginaDetalle.abrir(
    context,
    PaginaDetalle(
      titulo: '${c.sabor ?? ''} · ${c.presentacion ?? ''}',
      subtitulo: 'Llenadora · ${fmtFecha(c.fecha)} · Turno ${c.turno.etiqueta}',
      estado: c.estado.etiqueta,
      colorEstado: color,
      secciones: [
        SeccionDetalle(titulo: 'Producción', filas: [
          ('Botellas llenadas', n(c.botellasLlenadas)),
          ('Botellas desechadas', n(c.botellasDesechadas)),
          ('Rebalse', n(c.rebalse)),
          ('Motivo de la merma', c.motivoMerma),
        ]),
        SeccionDetalle(titulo: 'Jarabe y tapas', filas: [
          ('Lote del preparado', c.nLotePreparado),
          ('Tanque', c.tanque),
          ('Tapa', c.itemTapaDetalle),
          ('Tapas usadas', n(c.tapasUsadas)),
          ('Tapas desechadas', n(c.tapasDesechadas)),
        ]),
        SeccionDetalle(titulo: 'Tiempos', filas: [
          ('Inicio', fmtFechaHora(c.horaInicio)),
          ('Fin', c.horaFin == null ? 'En curso' : fmtFechaHora(c.horaFin)),
          ('Duración', c.duracion == null ? null : '${c.duracion!.inMinutes} min'),
          ('Responsable', c.responsableNombre),
        ]),
        SeccionDetalle(filas: [('Observaciones', c.observaciones)]),
      ],
    ),
  );
}
