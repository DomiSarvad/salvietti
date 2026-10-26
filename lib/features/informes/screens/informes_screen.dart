import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
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

/// Informes por área para el Gerente: resultados de la semana, del mes, del año
/// o de un rango de fechas, con gráfico (y proyección si el período está en
/// curso), indicadores y detalle, exportables a PDF y Excel. Solo UI.
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
  AreaInforme.plan: Icons.table_chart_outlined,
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
    texto: '"General" resume todo; cada área, su detalle.',
  );
  final _pasoBuscar = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Buscar y descargar',
    texto: 'Escribí un sabor, producto o indicador. PDF y Excel bajan lo que ves.',
  );
  final _pasoPeriodo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Período',
    texto: 'Semana, mes o año, o un rango con Desde/Hasta.',
  );
  final _buscador = TextEditingController();
  Timer? _esperaTexto;
  bool _exportando = false;

  @override
  void dispose() {
    _esperaTexto?.cancel();
    _buscador.dispose();
    super.dispose();
  }

  /// Se aplica cuando se deja de escribir (cada búsqueda recalcula el informe).
  void _alEscribir(InformesService svc, String t) {
    setState(() {}); // muestra/oculta la "x"
    _esperaTexto?.cancel();
    _esperaTexto = Timer(const Duration(milliseconds: 350), () => svc.buscar(t));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'informes', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoAreas, _pasoBuscar, _pasoPeriodo];

  Future<void> _elegirFecha(InformesService svc, {required bool desde}) async {
    final hoy = DateTime.now();
    final actual = desde ? svc.rango.desde : svc.rango.ultimoDia;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual.isAfter(hoy) ? hoy : actual,
      firstDate: DateTime(2020),
      lastDate: hoy,
      helpText: desde ? 'Desde' : 'Hasta',
    );
    if (elegida == null) return;
    desde ? svc.elegirDesde(elegida) : svc.elegirHasta(elegida);
  }

  /// Mismo aspecto que los campos Desde/Hasta del buscador de las listas.
  /// Siempre muestran el rango que se está viendo; la "x" solo aparece en un
  /// rango elegido a mano, y vuelve a la semana/mes/año del selector.
  Widget _campoFecha(InformesService svc, {required bool desde}) {
    final porFechas = svc.rango.periodo == PeriodoInforme.fechas;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: svc.cargando ? null : () => _elegirFecha(svc, desde: desde),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: desde ? 'Desde' : 'Hasta',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.event_outlined, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: porFechas
              ? IconButton(
                  tooltip: 'Volver a ${svc.periodoBase.etiqueta.toLowerCase()}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: svc.cargando ? null : svc.quitarFechas,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(fmtFecha(desde ? svc.rango.desde : svc.rango.ultimoDia),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _botonExportar(InformeArea? i, InformesService svc, {required bool pdf}) => Tooltip(
        message: pdf ? 'Descargar en PDF lo que se ve' : 'Descargar en Excel lo que se ve',
        child: IconButton.outlined(
          onPressed:
              i == null || svc.cargando || _exportando ? null : () => _exportar(i, pdf: pdf),
          style: IconButton.styleFrom(
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(pdf ? Icons.picture_as_pdf_outlined : Icons.table_view_outlined,
              color: pdf ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
        ),
      );

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
        // Mismo buscador que las listas: texto + PDF/Excel arriba, fechas abajo.
        _pasoBuscar.envolver(Row(children: [
          Expanded(
            child: TextField(
              controller: _buscador,
              onChanged: (t) => _alEscribir(svc, t),
              decoration: InputDecoration(
                hintText: 'Buscar sabor, producto o indicador…',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscador.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _buscador.clear();
                          _alEscribir(svc, '');
                        }),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _botonExportar(i, svc, pdf: true),
          _botonExportar(i, svc, pdf: false),
        ])),
        const SizedBox(height: 8),
        _pasoPeriodo.envolver(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 130,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Ver por',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PeriodoInforme>(
                    isDense: true,
                    isExpanded: true,
                    // Con Desde/Hasta elegidos a mano no es ninguno de los tres.
                    value: svc.rango.periodo == PeriodoInforme.fechas ? null : svc.rango.periodo,
                    hint: const Text('Fechas'),
                    items: const [
                      DropdownMenuItem(value: PeriodoInforme.semana, child: Text('Semana')),
                      DropdownMenuItem(value: PeriodoInforme.mes, child: Text('Mes')),
                      DropdownMenuItem(value: PeriodoInforme.anio, child: Text('Año')),
                    ],
                    onChanged: svc.cargando
                        ? null
                        : (p) {
                            if (p == null) return;
                            // Elegir la misma opción estando en "Fechas" vuelve a ella.
                            p == svc.periodoBase && svc.rango.periodo == PeriodoInforme.fechas
                                ? svc.quitarFechas()
                                : svc.elegirPeriodo(p);
                          },
                  ),
                ),
              ),
            ),
            // El título del período se achica (hasta 2 líneas) en vez de empujar
            // la flecha de la derecha fuera de la pantalla en un celular angosto.
            IconButton(
                tooltip: 'Período anterior',
                onPressed: svc.cargando ? null : svc.anterior,
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(svc.rango.titulo,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
                tooltip: 'Período siguiente',
                onPressed: svc.cargando || !svc.puedeAvanzar ? null : svc.siguiente,
                icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _campoFecha(svc, desde: true)),
            const SizedBox(width: 8),
            Expanded(child: _campoFecha(svc, desde: false)),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.compare_arrows, size: 18),
              label: Text(switch (svc.rango.periodo) {
                PeriodoInforme.semana => 'Comparar con la semana anterior',
                PeriodoInforme.mes => 'Comparar con el mes anterior',
                PeriodoInforme.anio => 'Comparar con el año anterior',
                PeriodoInforme.fechas => 'Comparar con el período anterior',
              }),
              selected: svc.comparar,
              onSelected: svc.cargando ? null : (_) => svc.alternarComparar(),
            ),
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
          if (i.anteriores != null) ...[
            const SizedBox(height: 16),
            _Comparacion(i: i),
          ],
          if (i.tieneProyeccion) ...[
            const SizedBox(height: 16),
            _Proyeccion(i: i),
          ],
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

  /// En la pantalla completa: más alto, sin la tarjeta ni el botón de ampliar.
  final bool ampliado;
  const _Grafico({required this.i, this.ampliado = false});

  double _proy(int s, int b) => i.series[s].proyeccion?[b] ?? 0;
  double _ant(int s, int b) {
    final a = i.anteriores;
    return a == null || s >= a.length ? 0 : a[s].valores[b];
  }

  bool get _compara => i.anteriores != null;

  /// Pantalla completa solo para el gráfico. En el celular se pone horizontal
  /// (entra el año entero sin apretar las barras) y vuelve al cerrar.
  static Future<void> ampliar(BuildContext context, InformeArea i) async {
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text('${i.tituloGrafico} · ${i.rango.titulo}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 12),
            child: _Grafico(i: i, ampliado: true),
          ),
        ),
      ),
    ));
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  Widget build(BuildContext context) {
    final barras = i.barrasVisibles;
    var maximo = 0.0;
    for (var s = 0; s < i.series.length; s++) {
      for (var b = 0; b < barras; b++) {
        final v = i.series[s].valores[b] + _proy(s, b);
        if (v > maximo) maximo = v;
        if (_ant(s, b) > maximo) maximo = _ant(s, b);
      }
    }
    final titulo = Row(children: [
      Expanded(child: Text(i.tituloGrafico, style: const TextStyle(fontWeight: FontWeight.w700))),
      if (!ampliado && maximo > 0)
        IconButton(
          tooltip: 'Ver más grande',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_full, size: 20),
          onPressed: () => ampliar(context, i),
        ),
    ]);
    if (maximo <= 0) {
      return _Tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titulo,
        const SizedBox(height: 6),
        const Text('Sin datos en este período.', style: TextStyle(color: Colors.black54)),
      ]));
    }
    final rodsPorGrupo = i.series.length * (_compara ? 2 : 1);
    // Con muchas barras (un rango de 31 días) se muestra una etiqueta cada
    // tantas, para que no se pisen.
    final cadaCuantas = barras > (ampliado ? 31 : 16) ? (barras / (ampliado ? 16 : 8)).ceil() : 1;
    final chart = LayoutBuilder(builder: (context, c) {
      final porGrupo = (c.maxWidth - 50) / barras;
      final ancho = (porGrupo * 0.75 / rodsPorGrupo).clamp(2.0, ampliado ? 28.0 : 18.0);
      final grafico = BarChart(BarChartData(
        maxY: maximo * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) {
              final s = _compara ? ri ~/ 2 : ri;
              final esAnterior = _compara && ri.isOdd;
              final etiqueta = i.rango.etiquetas[g.x];
              if (esAnterior) {
                return BarTooltipItem(
                    '${i.series[s].nombre} · ${i.tituloAnterior}\n${fmtNum(_ant(s, g.x))}',
                    const TextStyle(color: Colors.white, fontSize: 11));
              }
              final p = _proy(s, g.x);
              return BarTooltipItem(
                  '${i.series[s].nombre} · $etiqueta\n${fmtNum(i.series[s].valores[g.x])}'
                  '${p > 0 ? '\n+ ${fmtNum(p, decimales: 0)} estimado' : ''}',
                  const TextStyle(color: Colors.white, fontSize: 11));
            },
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
                  style: TextStyle(fontSize: ampliado ? 11 : 9, color: Colors.black45)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final b = v.toInt();
                if (b < 0 || b >= barras || b % cadaCuantas != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(i.rango.etiquetas[b],
                      style: TextStyle(fontSize: ampliado ? 11 : 9, color: Colors.black54)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var b = 0; b < barras; b++)
            BarChartGroupData(x: b, barsSpace: barras > 16 ? 1 : 3, barRods: [
              for (var s = 0; s < i.series.length; s++) ...[
                () {
                  final real = i.series[s].valores[b];
                  final p = _proy(s, b);
                  final color = _colores[s % _colores.length];
                  return BarChartRodData(
                    toY: real + p,
                    width: ancho,
                    color: color,
                    // Lo estimado va arriba de lo real, del mismo color pero claro.
                    rodStackItems: p > 0
                        ? [
                            BarChartRodStackItem(0, real, color),
                            BarChartRodStackItem(real, real + p, color.withValues(alpha: 0.25)),
                          ]
                        : const [],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  );
                }(),
                // El período anterior, al lado y en gris del mismo tono.
                if (_compara)
                  BarChartRodData(
                    toY: _ant(s, b),
                    width: ancho,
                    color: _colores[s % _colores.length].withValues(alpha: 0.35),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
              ],
            ]),
        ],
      ));
      return ampliado ? grafico : SizedBox(height: 220, child: grafico);
    });
    final leyenda = Wrap(spacing: 14, runSpacing: 4, children: [
      for (var s = 0; s < i.series.length; s++) ...[
        _ItemLeyenda(color: _colores[s % _colores.length], texto: i.series[s].nombre),
        if (_compara)
          _ItemLeyenda(
              color: _colores[s % _colores.length].withValues(alpha: 0.35),
              texto: '${i.series[s].nombre} (${i.tituloAnterior})'),
      ],
      if (i.tieneProyeccion)
        _ItemLeyenda(
            color: _colores.first.withValues(alpha: 0.25), texto: 'Estimado (lo que falta de hoy en adelante)'),
    ]);
    final mostrarLeyenda = i.series.length > 1 || i.tieneProyeccion || _compara;

    if (ampliado) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: chart),
        if (mostrarLeyenda) ...[const SizedBox(height: 8), leyenda],
      ]);
    }
    return _Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titulo,
        const SizedBox(height: 6),
        chart,
        if (mostrarLeyenda) ...[const SizedBox(height: 8), leyenda],
      ]),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _ItemLeyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ]);
}

/// Este período contra el anterior, "a la misma altura": si el período está
/// en curso se compara solo lo que va (ej. enero–octubre de los dos años),
/// para no comparar un año a medias contra uno entero.
class _Comparacion extends StatelessWidget {
  final InformeArea i;
  const _Comparacion({required this.i});

  @override
  Widget build(BuildContext context) {
    final ant = i.anteriores!;
    final n = i.barrasVisibles;
    final enCurso = i.barrasHastaHoy != null;
    final hasta = enCurso ? ' (${i.rango.etiquetas.first}–${i.rango.etiquetas[n - 1]})' : '';
    return _Tarjeta(
      titulo: 'Comparado con ${i.tituloAnterior}$hasta',
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (var s = 0; s < i.series.length && s < ant.length; s++)
          () {
            final actual = InformeArea.sumaHasta(i.series[s], n);
            final antes = InformeArea.sumaHasta(ant[s], n);
            final variacion = antes <= 0 ? null : (actual - antes) * 100 / antes;
            final sube = (variacion ?? 0) >= 0;
            return Container(
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _colores[s % _colores.length].withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.series[s].nombre, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fmtNum(actual, decimales: 0),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  if (variacion != null)
                    Text('${sube ? '▲' : '▼'} ${fmtNum(variacion.abs(), decimales: 1)} %',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: sube ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                ]),
                Text('Antes: ${fmtNum(antes, decimales: 0)}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            );
          }(),
      ]),
    );
  }
}

/// Cuánto se lleva y cuánto se estima al cierre del período en curso.
class _Proyeccion extends StatelessWidget {
  final InformeArea i;
  const _Proyeccion({required this.i});

  String get _cierre => switch (i.rango.periodo) {
        PeriodoInforme.semana => 'de la semana',
        PeriodoInforme.mes => 'del mes',
        PeriodoInforme.anio => 'del año',
        PeriodoInforme.fechas => 'del período',
      };

  @override
  Widget build(BuildContext context) => _Tarjeta(
        titulo: 'Proyección al cierre $_cierre',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var s = 0; s < i.series.length; s++)
              Container(
                constraints: const BoxConstraints(minWidth: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _colores[s % _colores.length].withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.series[s].nombre, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(fmtNum(i.series[s].totalProyectado ?? 0, decimales: 0),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _colores[s % _colores.length])),
                  Text('Van ${fmtNum(i.series[s].total, decimales: 0)}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ]),
              ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Estimado al ritmo promedio por día de lo que va del período. Es una referencia, '
            'no un dato registrado.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ]),
      );
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
