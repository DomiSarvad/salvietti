import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/salidas_modelos.dart';
import '../repositories/salidas_repository.dart';
import '../services/salidas_service.dart';
import 'reporte_detalle_screen.dart';

/// Registro de salidas: reportes de producción por día/turno, con sus
/// sabores y formatos, y la Planilla de producción (se arma sola). Solo UI;
/// las reglas viven en el service.
class SalidasScreen extends StatelessWidget {
  const SalidasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => SalidasService(SupabaseSalidasRepository(), usuario)..iniciar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatelessWidget {
  const _Vista();

  Future<void> _nuevoReporte(BuildContext context, SalidasService svc) async {
    final turno = await showDialog<Turno>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Abrir reporte de hoy'),
        children: [
          for (final t in Turno.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t.etiqueta),
            ),
        ],
      ),
    );
    if (turno == null || !context.mounted) return;
    final error = await svc.crearReporte(turno.id);
    if (!context.mounted) return;
    if (error == null) {
      mostrarExito(context, 'Reporte abierto.');
    } else {
      mostrarError(context, error);
    }
  }

  Future<void> _abrir(BuildContext context, SalidasService svc, ReporteSalidas r) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: svc,
          child: ReporteDetalleScreen(servicio: svc, reporte: r),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SalidasService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Registro de salidas.'),
        ),
      );
    }
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Registro de salidas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (svc.puedeCrear)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _nuevoReporte(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Abrir reporte'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (svc.abiertos.isNotEmpty) ...[
          const Text('Abiertos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          for (final r in svc.abiertos) _TarjetaReporte(svc: svc, r: r, onTap: () => _abrir(context, svc, r)),
          const SizedBox(height: 20),
        ],
        const Text('Historial', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (svc.cerrados.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay reportes cerrados.', style: TextStyle(color: Colors.black54)),
          )
        else
          for (final r in svc.cerrados) _TarjetaReporte(svc: svc, r: r, onTap: () => _abrir(context, svc, r)),
        const SizedBox(height: 20),
        _SeccionPlanilla(svc: svc),
      ],
    );
  }
}

class _TarjetaReporte extends StatelessWidget {
  final SalidasService svc;
  final ReporteSalidas r;
  final VoidCallback onTap;
  const _TarjetaReporte({required this.svc, required this.r, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final abierto = r.estado == EstadoReporte.abierto;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        title: Text('${fmtFecha(r.fecha)} · ${r.turno.etiqueta}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            'Inicio: ${fmtFechaHora(r.horaInicioDia)}'
            '${r.horaFinDia == null ? '' : ' · Fin: ${fmtFechaHora(r.horaFinDia)}'}'
            ' · ${r.responsableNombre ?? '—'}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: (abierto ? const Color(0xFFD97706) : const Color(0xFF16A34A)).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text(r.estado.etiqueta,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: abierto ? const Color(0xFFD97706) : const Color(0xFF16A34A))),
        ),
      ),
    );
  }
}

class _SeccionPlanilla extends StatelessWidget {
  final SalidasService svc;
  const _SeccionPlanilla({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Planilla de producción', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Se arma sola con lo cargado en los reportes de arriba.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          if (svc.planilla.isEmpty)
            const Text('Todavía no hay datos.', style: TextStyle(color: Colors.black54))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 40,
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Sabor')),
                  DataColumn(label: Text('Formato')),
                  DataColumn(label: Text('Reportes'), numeric: true),
                  DataColumn(label: Text('Total botellas'), numeric: true),
                ],
                rows: [
                  for (final f in svc.planilla)
                    DataRow(cells: [
                      DataCell(Text(fmtFecha(f.fecha))),
                      DataCell(Text(f.sabor)),
                      DataCell(Text('${f.presentacion} (${f.material == 'pet' ? 'PET' : 'Vidrio'})')),
                      DataCell(Text('${f.reportes}')),
                      DataCell(Text(f.totalBotellas == null ? '—' : fmtNum(f.totalBotellas, decimales: 0))),
                    ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
