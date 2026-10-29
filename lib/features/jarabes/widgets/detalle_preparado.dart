import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../models/jarabes_modelos.dart';
import '../services/jarabes_service.dart';

Color _colorEstado(EstadoPreparado e) => switch (e) {
      EstadoPreparado.enCurso => const Color(0xFFD97706),
      EstadoPreparado.finalizada => const Color(0xFF16A34A),
      EstadoPreparado.anulada => Colors.black45,
    };

/// Detalle de un preparado y, debajo, los demás preparados de ese mismo día
/// (con el total del día). Tocar otro abre su detalle en lugar de este.
Future<void> abrirDetallePreparado(BuildContext context, JarabesService svc, Preparado p) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _pagina(svc, p)));

Widget _pagina(JarabesService svc, Preparado p) {
  final delDia = svc.preparadosDelDia(p.fecha);
  final finalizados = delDia.where((x) => x.estado == EstadoPreparado.finalizada);
  final litrosDia = finalizados.fold<double>(0, (s, x) => s + (x.litros ?? 0));
  final preparadosDia = finalizados.fold<double>(0, (s, x) => s + x.cantidadPreparados);

  return PaginaDetalle(
    titulo: '${p.sabor ?? ''} · ${p.sinSubir ? 'Lote al subir' : 'Lote ${p.nLote}'}',
    subtitulo: fmtFecha(p.fecha),
    estado: p.estado.etiqueta,
    colorEstado: _colorEstado(p.estado),
    secciones: [
      SeccionDetalle(titulo: 'Preparado', filas: [
        ('Cantidad', '${fmtNum(p.cantidadPreparados, decimales: 2)} preparado(s)'),
        ('Litros', p.litros == null ? null : '${fmtNum(p.litros, decimales: 0)} L'),
        ('Tanque', p.tanque?.toString()),
        ('Brix', p.brix == null ? null : fmtNum(p.brix, decimales: 1)),
      ]),
      SeccionDetalle(titulo: 'Tiempos', filas: [
        ('Inicio', fmtFechaHora(p.horaInicio)),
        ('Fin', p.horaFin == null ? 'En curso' : fmtFechaHora(p.horaFin)),
        ('Duración', p.duracion == null ? null : '${p.duracion!.inMinutes} min'),
        ('Responsable', p.responsableNombre),
      ]),
      SeccionDetalle(filas: [('Observaciones', p.observaciones)]),
    ],
    extra: [
      Text('Preparados del ${fmtFecha(p.fecha)} (${delDia.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      Text(
        'Finalizados: ${fmtNum(preparadosDia, decimales: 2)} preparado(s) · '
        '${fmtNum(litrosDia, decimales: 0)} L',
        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB)),
        ),
        child: Column(children: [
          for (var i = 0; i < delDia.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            Builder(builder: (context) {
              final x = delDia[i];
              final esEste = x.id == p.id;
              return ListTile(
                selected: esEste,
                selectedColor: AppColors.primario,
                leading: Icon(Icons.circle, size: 12, color: _colorEstado(x.estado)),
                title: Text('${x.sabor ?? ''} · Lote ${x.nLote}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${fmtFechaHora(x.horaInicio).split(' ').last} · ${fmtNum(x.cantidadPreparados, decimales: 2)} prep.'
                    '${x.litros == null ? '' : ' · ${fmtNum(x.litros, decimales: 0)} L'}'),
                trailing: esEste ? null : const Icon(Icons.chevron_right),
                onTap: esEste
                    ? null
                    : () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(builder: (_) => _pagina(svc, x))),
              );
            }),
          ],
        ]),
      ),
    ],
  );
}
