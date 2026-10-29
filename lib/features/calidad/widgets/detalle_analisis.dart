import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/calidad_modelos.dart';

/// Detalle de un análisis de Calidad (tocar su tarjeta en el historial).
Future<void> abrirDetalleAnalisis(BuildContext context, AnalisisCalidad a) =>
    PaginaDetalle.abrir(
      context,
      PaginaDetalle(
        titulo: '${a.sabor ?? ''}${a.nLote == null ? '' : ' · Lote ${a.nLote}'}',
        subtitulo: 'Control de Calidad · ${fmtFecha(a.fecha)}',
        estado: a.conforme ? 'Conforme' : 'No conforme',
        colorEstado: a.conforme ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        secciones: [
          SeccionDetalle(titulo: 'Mediciones', filas: [
            ('Brix diluido', a.brixDiluido == null ? null : fmtNum(a.brixDiluido, decimales: 1)),
            ('pH', a.ph == null ? null : fmtNum(a.ph, decimales: 2)),
            ('Aspecto', a.aspecto),
          ]),
          SeccionDetalle(filas: [
            ('Acción tomada', a.accionTomada),
            ('Observaciones', a.observaciones),
            ('Responsable', a.responsableNombre),
          ]),
        ],
      ),
    );
