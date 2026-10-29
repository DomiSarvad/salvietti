import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/codificacion_modelos.dart';

/// Detalle de una corrida de Codificación (tocar su tarjeta en el historial).
Future<void> abrirDetalleCodificacion(BuildContext context, CorridaCodificacion c) {
  final color = switch (c.estado) {
    EstadoCorrida.enCurso => const Color(0xFFD97706),
    EstadoCorrida.finalizada => const Color(0xFF16A34A),
    EstadoCorrida.anulada => Colors.black45,
  };
  String? n(num? v, [int dec = 0]) => v == null || v == 0 ? null : fmtNum(v, decimales: dec);
  return PaginaDetalle.abrir(
    context,
    PaginaDetalle(
      titulo: '${c.sabor ?? ''} · ${c.presentacion ?? ''}',
      subtitulo: 'Codificación · ${fmtFecha(c.fecha)} · Turno ${c.turno.etiqueta}',
      estado: c.estado.etiqueta,
      colorEstado: color,
      secciones: [
        SeccionDetalle(titulo: 'Producción', filas: [
          ('Botellas codificadas', n(c.botellasCodificadas)),
          ('Código impreso', c.codigoImpreso),
          ('Lote', c.nLote),
        ]),
        SeccionDetalle(titulo: 'Merma', filas: [
          ('Botellas mal tapadas', n(c.botellasMalTapadas)),
          ('Tapas mal tapadas', n(c.tapasMalTapadas)),
          ('Impurezas', n(c.impurezas)),
          ('Motivo', c.motivoMerma),
        ]),
        SeccionDetalle(titulo: 'Solvente y tinta', filas: [
          ('Solvente', c.itemSolventeDetalle),
          ('Solvente usado', n(c.solventeUsado, 2)),
          ('Tinta', c.itemTintaDetalle),
          ('Tinta usada', n(c.tintaUsada, 2)),
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
