import 'package:flutter/material.dart';
import '../../../shared/filtros/barra_filtros.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../utils/formatters.dart';
import '../../jarabes/models/jarabes_modelos.dart';

Color _color(EstadoReceta e) => switch (e) {
      EstadoReceta.propuesta => const Color(0xFFD97706),
      EstadoReceta.activa => const Color(0xFF16A34A),
      EstadoReceta.inactiva => Colors.black45,
      EstadoReceta.rechazada => const Color(0xFFDC2626),
    };

String _estado(EstadoReceta e) => switch (e) {
      EstadoReceta.propuesta => 'Pendiente',
      EstadoReceta.activa => 'Aprobada',
      EstadoReceta.inactiva => 'Aprobada (ya reemplazada)',
      EstadoReceta.rechazada => 'Rechazada',
    };

/// Pestaña "Recetas" de Solicitudes: el historial de propuestas de receta
/// (se aprueban en Jarabes). Tocar una abre su detalle.
class ListaRecetas extends StatelessWidget {
  final List<RecetaPropuesta> recetas;
  final bool filtrando;
  const ListaRecetas({super.key, required this.recetas, required this.filtrando});

  @override
  Widget build(BuildContext context) {
    if (recetas.isEmpty) {
      return filtrando
          ? const SinResultados()
          : const Center(
              child: Text('No hay propuestas de receta en los últimos 90 días.',
                  style: TextStyle(color: Colors.black54)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.separated(
          itemCount: recetas.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56, color: Color(0xFFE8ECEF)),
          itemBuilder: (context, i) {
            final r = recetas[i];
            final color = _color(r.estado);
            return Material(
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(Icons.receipt_long_outlined, color: color, size: 20),
                ),
                title: Text('Receta de ${r.sabor ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${r.creadaPorNombre ?? '—'} · ${fmtFecha(r.creadaEn)}'
                  '${(r.motivoRechazo ?? '').isEmpty ? '' : '\nMotivo: ${r.motivoRechazo}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_estado(r.estado),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                onTap: () => _abrir(context, r),
              ),
            );
          },
        ),
      ),
    );
  }

  void _abrir(BuildContext context, RecetaPropuesta r) => PaginaDetalle.abrir(
        context,
        PaginaDetalle(
          titulo: 'Receta de ${r.sabor ?? ''}',
          subtitulo: 'Propuesta el ${fmtFecha(r.creadaEn)}',
          estado: _estado(r.estado),
          colorEstado: _color(r.estado),
          nombrePdf: 'Receta ${r.sabor ?? ''} ${fmtFecha(r.creadaEn).replaceAll('/', '-')}',
          firmasPdf: const ['Control de Calidad', 'Jefe de Producción', 'Gerencia'],
          secciones: [
            SeccionDetalle(titulo: 'Quién intervino', filas: [
              ('Propuesta por', r.creadaPorNombre),
              ('Visto bueno de Calidad',
                  r.aprobadaCalidadEn == null ? 'Pendiente' : '${r.aprobadaCalidadNombre ?? '—'}, ${fmtFecha(r.aprobadaCalidadEn)}'),
              ('Visto bueno de Producción',
                  r.aprobadaProduccionEn == null ? 'Pendiente' : '${r.aprobadaProduccionNombre ?? '—'}, ${fmtFecha(r.aprobadaProduccionEn)}'),
              (r.estado == EstadoReceta.rechazada ? 'Rechazada por' : 'Confirmada por',
                  r.resueltaEn == null ? null : '${r.resueltaPorNombre ?? '—'}, ${fmtFecha(r.resueltaEn)}'),
              ('Motivo del rechazo', r.motivoRechazo),
            ]),
            SeccionDetalle(titulo: 'Insumos por preparado', filas: [
              for (final i in r.items) (i.detalle, '${fmtNum(i.cantidad)} ${i.unidad}'),
            ]),
          ],
          extra: [
            if (r.estado == EstadoReceta.propuesta)
              const Text('Se aprueba desde Jarabes, en "Recetas por aprobar".',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          ],
        ),
      );
}
