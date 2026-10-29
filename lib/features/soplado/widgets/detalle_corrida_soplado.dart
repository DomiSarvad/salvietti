import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/soplado_modelos.dart';

/// Detalle de una corrida de Soplado (tocar su tarjeta en el historial).
Future<void> abrirDetalleSoplado(BuildContext context, CorridaSoplado c) {
  final color = switch (c.estado) {
    EstadoCorrida.enCurso => const Color(0xFFD97706),
    EstadoCorrida.finalizada => const Color(0xFF16A34A),
    EstadoCorrida.anulada => Colors.black45,
  };
  String? n(num? v) => v == null ? null : fmtNum(v, decimales: 0);
  return PaginaDetalle.abrir(
    context,
    PaginaDetalle(
      titulo: '${c.sabor ?? ''} · ${c.presentacion ?? ''}',
      subtitulo: 'Soplado · ${fmtFecha(c.fecha)}',
      estado: c.estado.etiqueta,
      colorEstado: color,
      secciones: [
        SeccionDetalle(titulo: 'Producción', filas: [
          ('Botellas sopladas', n(c.botellasSopladas)),
          ('Preformas usadas', n(c.preformasUsadas)),
          ('Botellas etiquetadas', n(c.botellasEtiquetadas)),
        ]),
        if (c.tieneMerma || (c.tiempoParadaMinutos ?? 0) > 0)
          SeccionDetalle(titulo: 'Merma y paradas', filas: [
            ('Merma de preforma', c.mermaPreforma > 0 ? '${c.mermaPreforma}' : null),
            ('Merma de soplado', c.mermaSoplado > 0 ? '${c.mermaSoplado}' : null),
            ('Merma de etiquetado', c.mermaEtiquetado > 0 ? '${c.mermaEtiquetado}' : null),
            ('Motivo de la merma', c.motivoMerma),
            ('Parada', (c.tiempoParadaMinutos ?? 0) > 0 ? '${c.tiempoParadaMinutos} min' : null),
            ('Motivo de la parada', c.motivoParada),
          ]),
        SeccionDetalle(titulo: 'Preforma', filas: [
          ('Preforma', c.itemPreformaDetalle),
          ('Proveedor', c.proveedorNombre),
          ('Lote', c.lotePreforma),
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
