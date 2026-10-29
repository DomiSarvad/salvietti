import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/mermas_modelos.dart';

String _area(String area) => switch (area) {
      'soplado' => 'Soplado',
      'llenadora' => 'Llenadora',
      'codificacion' => 'Codificación',
      'jarabes' => 'Jarabes',
      'calidad' => 'Calidad',
      'vidrio' => 'Vidrio',
      _ => area,
    };

/// Detalle de un evento de merma (tocar su tarjeta en el historial).
Future<void> abrirDetalleMerma(BuildContext context, EventoMerma e) => PaginaDetalle.abrir(
      context,
      PaginaDetalle(
        titulo: '${_area(e.area)} · ${e.sabor}',
        subtitulo: 'Merma · ${fmtFecha(e.fecha)}',
        estado: e.alerta ? 'Supera el 3 %' : 'Dentro de lo normal',
        colorEstado: e.alerta ? const Color(0xFFDC2626) : AppColors.primario,
        secciones: [
          SeccionDetalle(filas: [
            ('Área', _area(e.area)),
            ('Sabor', e.sabor),
            ('Presentación', e.presentacion),
          ]),
          SeccionDetalle(titulo: 'Cantidades', filas: [
            ('Merma', fmtNum(e.totalMerma, decimales: 0)),
            ('Producido', e.producido == null ? null : fmtNum(e.producido, decimales: 0)),
            ('Porcentaje', e.porcentaje == null ? null : '${fmtNum(e.porcentaje, decimales: 1)} %'),
          ]),
          SeccionDetalle(filas: [('Motivo', e.motivo)]),
        ],
      ),
    );
