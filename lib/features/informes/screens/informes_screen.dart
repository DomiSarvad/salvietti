import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/informes_modelos.dart';
import '../repositories/informes_repository.dart';
import '../services/informes_export_service.dart';
import '../services/informes_service.dart';

/// Informes por área para el Gerente: resultados de la semana o del mes, con
/// gráfico, indicadores y detalle, exportables a PDF y Excel. Solo UI.
class InformesScreen extends StatelessWidget {
  const InformesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => InformesService(SupabaseInformesRepository(), usuario)..iniciar(),
      child: const _Vista(),
    );
  }
}

const _colores = [AppColors.primario, AppColors.secundario, Color(0xFF64748B), Color(0xFFDC2626)];

const _iconos = {
  AreaInforme.general: Icons.dashboard_outlined,
  AreaInforme.jarabes: Icons.water_drop_outlined,
  AreaInforme.soplado: Icons.air_outlined,
  AreaInforme.llenadora: Icons.local_drink_outlined,
  AreaInforme.codificacion: Icons.qr_code_2,
  AreaInforme.calidad: Icons.science_outlined,
  AreaInforme.produccion: Icons.outbox_outlined,
  AreaInforme.mermas: Icons.report_problem_outlined,
  AreaInforme.almacen: Icons.warehouse_outlined,
  AreaInforme.soda: Icons.science_outlined,
};

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoAreas = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Áreas',
    texto: '"General" resume todo; cada área muestra sus resultados en detalle.',
  );
  final _pasoPeriodo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Semana o mes',
    texto: 'Semanal muestra una barra por día; Mensual, una por semana. Con las flechas '
        'se va a períodos anteriores.',
  );
  final _pasoExportar = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'PDF y Excel',
    texto: 'Descarga exactamente este informe (el área y el período elegidos), listo para '
        'imprimir o para trabajarlo en Excel.',
  );
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'informes', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoAreas, _pasoPeriodo, _pasoExportar];

  Future<void> _exportar(InformeArea i, {required bool pdf}) async {
    final responsable = context.read<AuthService>().usuarioActual?.nombreCompleto ?? '—';
    setState(() => _exportando = true);
    try {
      if (pdf) {
        final bytes = await InformesExportService.pdf(i, responsable: responsable);
        await InformesExportService.guardarPdf(bytes, i);
      } else {
        final bytes = InformesExportService.excel(i, responsable: responsable);
        await InformesExportService.guardarExcel(bytes, i);
      }
      if (mounted) mostrarExito(context, pdf ? 'PDF generado.' : 'Excel generado.');
    } catch (e) {
      if (mounted) mostrarError(context, 'No se pudo generar el archivo.');
    }
    if (mounted) setState(() => _exportando = false);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<InformesService>();
    if (!svc.puedeVer) {
      return const Center(child: Text('Tu rol no tiene acceso a los informes.'));
    }
    final i = svc.informe;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          const Expanded(
            child: Text('Informes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          BotonAyuda(idTour: 'informes', pasos: _pasosAyuda),
        ]),
        const SizedBox(height: 10),
        _pasoAreas.envolver(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final a in AreaInforme.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(_iconos[a], size: 16,
                      color: a == svc.area ? Colors.white : AppColors.primario),
                  label: Text(a.titulo),
                  selected: a == svc.area,
                  selectedColor: AppColors.primario,
                  labelStyle: TextStyle(color: a == svc.area ? Colors.white : Colors.black87),
                  onSelected: (_) => svc.elegirArea(a),
                ),
              ),
          ]),
        )),
        const SizedBox(height: 10),
        _pasoPeriodo.envolver(Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<PeriodoInforme>(
              segments: [
                for (final p in PeriodoInforme.values) ButtonSegment(value: p, label: Text(p.etiqueta)),
              ],
              selected: {svc.rango.periodo},
              onSelectionChanged: (s) => svc.elegirPeriodo(s.first),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  tooltip: 'Período anterior',
                  onPressed: svc.cargando ? null : svc.anterior,
                  icon: const Icon(Icons.chevron_left)),
              Text(svc.rango.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                  tooltip: 'Período siguiente',
                  onPressed: svc.cargando || !svc.puedeAvanzar ? null : svc.siguiente,
                  icon: const Icon(Icons.chevron_right)),
            ]),
          ],
        )),
        const SizedBox(height: 8),
        _pasoExportar.envolver(Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: i == null || svc.cargando || _exportando ? null : () => _exportar(i, pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
          OutlinedButton.icon(
            onPressed: i == null || svc.cargando || _exportando ? null : () => _exportar(i, pdf: false),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Excel'),
          ),
        ])),
        const SizedBox(height: 16),
        if (svc.cargando)
          const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (svc.error != null)
          Column(children: [
            Text(svc.error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: svc.cargar, child: const Text('Reintentar')),
          ])
        else if (i != null) ...[
          _Kpis(i: i),
          const SizedBox(height: 16),
          _Grafico(i: i),
          const SizedBox(height: 16),
          _Tabla(i: i),
          if (i.nota != null) ...[
            const SizedBox(height: 8),
            Text(i.nota!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final String? titulo;
  final Widget child;
  const _Tarjeta({this.titulo, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (titulo != null) ...[
            Text(titulo!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
          ],
          child,
        ]),
      );
}

class _Kpis extends StatelessWidget {
  final InformeArea i;
  const _Kpis({required this.i});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final k in i.kpis)
            Container(
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: k.alerta ? const Color(0xFFDC2626) : const Color(0xFFE3E7EB),
                    width: k.alerta ? 1.5 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k.etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                Text(k.valor,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: k.alerta ? const Color(0xFFDC2626) : Colors.black87)),
              ]),
            ),
        ],
      );
}

class _Grafico extends StatelessWidget {
  final InformeArea i;
  const _Grafico({required this.i});

  @override
  Widget build(BuildContext context) {
    final maximo = i.series.expand((s) => s.valores).fold<double>(0, (m, v) => v > m ? v : m);
    if (maximo <= 0) {
      return _Tarjeta(
          titulo: i.tituloGrafico,
          child: const Text('Sin datos en este período.', style: TextStyle(color: Colors.black54)));
    }
    final ancho = i.series.length > 1 ? 10.0 : 18.0;
    return _Tarjeta(
      titulo: i.tituloGrafico,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 220,
          child: BarChart(BarChartData(
            maxY: maximo * 1.15,
            alignment: BarChartAlignment.spaceAround,
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                    '${i.series[ri].nombre}\n${fmtNum(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, meta) => Text(fmtNum(v, decimales: 0),
                      style: const TextStyle(fontSize: 9, color: Colors.black45)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, meta) {
                    final b = v.toInt();
                    if (b < 0 || b >= i.rango.etiquetas.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(i.rango.etiquetas[b],
                          style: const TextStyle(fontSize: 9, color: Colors.black54)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var b = 0; b < i.rango.etiquetas.length; b++)
                BarChartGroupData(x: b, barsSpace: 3, barRods: [
                  for (var s = 0; s < i.series.length; s++)
                    BarChartRodData(
                      toY: i.series[s].valores[b],
                      width: ancho,
                      color: _colores[s % _colores.length],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                ]),
            ],
          )),
        ),
        if (i.series.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            for (var s = 0; s < i.series.length; s++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: _colores[s % _colores.length]),
                const SizedBox(width: 4),
                Text(i.series[s].nombre, style: const TextStyle(fontSize: 12)),
              ]),
          ]),
        ],
      ]),
    );
  }
}

class _Tabla extends StatelessWidget {
  final InformeArea i;
  const _Tabla({required this.i});

  @override
  Widget build(BuildContext context) {
    if (i.filas.isEmpty) {
      return _Tarjeta(
          titulo: i.tituloTabla,
          child: const Text('Sin datos en este período.', style: TextStyle(color: Colors.black54)));
    }
    return _Tarjeta(
      titulo: i.tituloTabla,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: 24,
          columns: [
            for (var c = 0; c < i.columnas.length; c++)
              DataColumn(label: Text(i.columnas[c]), numeric: c > 0 && i.area != AreaInforme.general),
          ],
          rows: [
            for (final f in i.filas) DataRow(cells: [for (final v in f) DataCell(Text(v))]),
          ],
        ),
      ),
    );
  }
}
