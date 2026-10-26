import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
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
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<SalidasService>().recargar(),
        child: const _Vista(),
      ),
    );
  }
}

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoAbrirReporte = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Abrir reporte',
    texto: 'El reporte del turno, para cargar lo producido.',
  );
  final _pasoHistorial = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Historial',
    texto: 'Reportes cerrados.',
  );
  final _pasoPlanilla = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Planilla de producción',
    texto: 'Se arma sola con los reportes.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'salidas', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoAbrirReporte, _pasoHistorial, _pasoPlanilla];

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

    // El historial de reportes cerrados puede crecer mucho: queda en un
    // SliverList de verdad (perezoso). A diferencia de otras pantallas, acá
    // la Planilla va DESPUÉS de esa lista sin límite — un `ListView` común
    // no sirve: su encabezado podía quedar mounteado a tiempo por ser el
    // primer ítem, pero la Planilla, al final, dependía de haber scrolleado
    // hasta ahí para existir en el árbol, y el tour la salteaba en silencio.
    // Con `SliverToBoxAdapter` tanto el encabezado como la Planilla se
    // montan siempre, sin importar cuántos reportes cerrados haya en medio.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(child: _encabezado(context, svc)),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: svc.cerrados.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Todavía no hay reportes cerrados.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final r = svc.cerrados[i];
                      return _TarjetaReporte(svc: svc, r: r, onTap: () => _abrir(context, svc, r));
                    },
                    childCount: svc.cerrados.length,
                  ),
                ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          sliver: SliverToBoxAdapter(child: _pasoPlanilla.envolver(_SeccionPlanilla(svc: svc))),
        ),
      ],
    );
  }

  Widget _encabezado(BuildContext context, SalidasService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Registro de salidas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'salidas', pasos: _pasosAyuda),
          ],
        ),
        if (svc.puedeCrear) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _pasoAbrirReporte.envolver(
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _nuevoReporte(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Abrir reporte'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (svc.abiertos.isNotEmpty) ...[
          const Text('Abiertos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          for (final r in svc.abiertos) _TarjetaReporte(svc: svc, r: r, onTap: () => _abrir(context, svc, r)),
          const SizedBox(height: 20),
        ],
        _pasoHistorial.envolver(
          const Text('Historial',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(height: 8),
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
