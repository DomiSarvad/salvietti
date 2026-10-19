import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../models/produccion.dart';
import '../../../services/auth_service.dart';
import '../../../services/produccion_service.dart';
import '../../../utils/formatters.dart';
import '../../inventario/models/existencia_item.dart';
import '../../presencia/widgets/aviso_conexion_areas.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../models/dashboard_modelos.dart';
import '../repositories/dashboard_repository.dart';
import '../services/dashboard_service.dart';

const _iconos = <String, IconData>{
  'general': Icons.warehouse_outlined,
  'jarabes': Icons.water_drop_outlined,
  'soplado': Icons.air_outlined,
  'soda_caustica': Icons.science_outlined,
};
const _colores = <String, Color>{
  'general': AppColors.primario,
  'jarabes': Color(0xFF2563EB),
  'soplado': Color(0xFFD97706),
  'soda_caustica': Color(0xFFDC2626),
};
IconData _iconoDe(String almacenId) =>
    _iconos[almacenId] ?? Icons.inventory_2_outlined;
Color _colorDe(String almacenId) => _colores[almacenId] ?? Colors.black54;

const _etiquetasArea = <String, String>{
  'soplado': 'Soplado',
  'llenadora': 'Llenadora',
  'codificacion': 'Codificación',
  'jarabes': 'Jarabes',
  'calidad': 'Calidad',
  'vidrio': 'Vidrio',
};
String _etiquetaArea(String area) => _etiquetasArea[area] ?? area;

/// Inicio: lo primero que ve cualquier rol al entrar. Un resumen por
/// almacén (según lo que el rol pueda ver — Módulo 1), el plan de
/// producción del día, lo que urge reponer y los últimos movimientos.
/// Todo sale de datos en vivo (`inv_existencia`/`inv_movimientos`); solo UI,
/// las reglas viven en el service.
class DashboardScreen extends StatelessWidget {
  /// Se llama con el id del almacén al tocar su tarjeta, para abrir
  /// Almacenes ya con ese almacén seleccionado.
  final void Function(String almacenId)? onAbrirInventario;

  /// Se llama al tocar la tarjeta "Plan de producción de hoy", para abrir
  /// esa pantalla dentro del mismo shell (en vez de un push aparte).
  final VoidCallback? onAbrirProduccion;
  const DashboardScreen(
      {super.key, this.onAbrirInventario, this.onAbrirProduccion});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          DashboardService(SupabaseDashboardRepository(), usuario)..iniciar(),
      child: _Vista(
          onAbrirInventario: onAbrirInventario,
          onAbrirProduccion: onAbrirProduccion),
    );
  }
}

class _Vista extends StatefulWidget {
  final void Function(String almacenId)? onAbrirInventario;
  final VoidCallback? onAbrirProduccion;
  const _Vista({this.onAbrirInventario, this.onAbrirProduccion});

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  PlanProduccion? _plan;
  bool _cargandoPlan = true;

  final _pasoAlmacenes = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Tus almacenes',
    texto: 'Un vistazo rápido: rojo, amarillo o verde según el peor ítem de cada uno. '
        'Tocá una tarjeta para entrar directo a ese almacén.',
  );
  final _pasoMenorStock = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Ítems con menor stock',
    texto: 'Lo más urgente primero: los críticos, después los bajos, y recién ahí por '
        'cantidad.',
  );
  final _pasoMovimientos = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Movimientos por almacén',
    texto: 'De qué almacén vienen los últimos movimientos registrados.',
  );
  final _pasoMermas = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Mermas por área',
    texto: '% de merma de cada área sobre lo producido; en rojo, lo que superó el 3 %.',
  );
  final _pasoPlan = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Plan de producción de hoy',
    texto: 'Lo que armó el Jefe de Producción para hoy. Tocá la tarjeta para ir a esa '
        'pantalla.',
  );
  final _pasoEnRiesgo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'En riesgo de desabastecimiento',
    texto: 'Ítems con 7 días o menos de existencia estimada, para reponer antes de que '
        'falten.',
  );

  @override
  void initState() {
    super.initState();
    _cargarPlan();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context,
            idTour: 'inicio', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() =>
      [_pasoAlmacenes, _pasoMenorStock, _pasoMovimientos, _pasoMermas, _pasoPlan, _pasoEnRiesgo];

  Future<void> _cargarPlan() async {
    final usuario = context.read<AuthService>().usuarioActual!;
    try {
      final plan = await ProduccionService.planDeHoy(usuario.id);
      if (mounted) {
        setState(() {
          _plan = plan;
          _cargandoPlan = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DashboardService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
        ]),
      );
    }
    if (svc.almacenesVisibles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a ningún almacén.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: svc.recargar,
      // SingleChildScrollView + Column en vez de ListView: un ListView arma
      // sus hijos de a poco a medida que entran en pantalla (o cerca), así
      // que las tarjetas de más abajo (Plan de hoy, En riesgo) todavía NO
      // existen en el árbol cuando el tour de ayuda arranca solo al entrar
      // — sus GlobalKey daban currentContext null y ese paso se salteaba
      // en silencio. Acá son pocas secciones grandes, no una lista larga
      // que necesite virtualizarse, así que no hay costo real en tenerlas
      // todas construidas desde el principio.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        // stretch, no start: varias tarjetas de acá abajo (Plan de hoy, En
        // riesgo, Movimientos recientes) no tienen un ancho propio — antes,
        // dentro del ListView, siempre ocupaban el ancho completo porque
        // ListView les daba esa restricción fija; con "start" en vez de
        // "stretch" habrían quedado angostas, del ancho de su contenido.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Inicio',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              BotonAyuda(idTour: 'inicio', pasos: _pasosAyuda),
            ]),
            // Qué áreas están sin internet (sus datos de acá pueden estar atrasados).
            const AvisoConexionAreas(roles: Rol.todos, margen: EdgeInsets.only(top: 12)),
            const SizedBox(height: 16),
            _pasoAlmacenes.envolver(
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [for (final r in svc.resumenes) _tarjetaAlmacen(r)],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _pasoMenorStock.envolver(_cardMenorStock(svc.menorStock)),
                _pasoMovimientos.envolver(_cardMovimientosPorAlmacen(svc.movimientos)),
                if (svc.puedeVerMermas)
                  _pasoMermas.envolver(
                    _cardMermas(svc.mermasPorArea, svc.mermasConAlerta.length),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_cargandoPlan && _plan != null)
              _pasoPlan.envolver(_cardPlanDelDia(_plan!)),
            if (!_cargandoPlan && _plan != null) const SizedBox(height: 24),
            _pasoEnRiesgo.envolver(_cardEnRiesgo(svc.enRiesgo.take(8).toList())),
            const SizedBox(height: 24),
            _cardMovimientosRecientes(svc.movimientos),
          ],
        ),
      ),
    );
  }

  /// Color semafórico (verde/amarillo/rojo) según el peor ítem del
  /// almacén — así se ve a simple vista si algo está mal, sin tener que
  /// leer el detalle. Los colores por almacén (`_colorDe`) se mantienen
  /// solo en los gráficos, para poder distinguir de qué almacén es cada
  /// sección.
  Color _colorSemaforo(ResumenAlmacen r) {
    final estado = r.estado;
    if (estado == null) return Colors.black38;
    return SemaforoStock.color(estado);
  }

  Widget _tarjetaAlmacen(ResumenAlmacen r) {
    final vacio = r.total == 0;
    final color = _colorSemaforo(r);

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onAbrirInventario == null
            ? null
            : () => widget.onAbrirInventario!(r.almacen.id),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconoDe(r.almacen.id), size: 22, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.almacen.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: color),
                ],
              ),
              const SizedBox(height: 10),
              if (vacio) ...[
                Text('Sin ítems',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 6),
                const Text('Todavía no hay ítems cargados en este almacén.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ] else ...[
                Text('${r.total}',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color)),
                const SizedBox(height: 6),
                Text(
                    '${r.optimos} óptimos · ${r.bajos} bajos · ${r.criticos} críticos',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardMenorStock(List<ExistenciaItem> items) {
    final maxBruto = items.isEmpty
        ? 0.0
        : items.map((i) => i.cantidadSistema).reduce((a, b) => a > b ? a : b);
    // Si el máximo es 0 (los peores ítems están todos en cero), usar ese 0
    // como techo del gráfico daría 0/0 = NaN y las barras se verían LLENAS
    // justo cuando el stock está más crítico. Con un techo fijo en ese caso,
    // todas quedan vacías, que es lo correcto.
    final maxY = maxBruto > 0 ? maxBruto * 1.2 : 10.0;

    return Container(
      width: 460,
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ítems con menor stock',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Sin ítems cargados todavía.',
                        style: TextStyle(color: Colors.black54)))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final e in items)
                        Row(
                          children: [
                            SizedBox(
                              width: 150,
                              child: Tooltip(
                                message: e.detalle,
                                child: Text(e.detalle,
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (e.cantidadSistema / maxY)
                                      .clamp(0.0, 1.0)
                                      .toDouble(),
                                  minHeight: 14,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation(
                                      _colorDe(e.almacenId)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 60,
                              child: Text(
                                  '${fmtNum(e.cantidadSistema, decimales: 0)} ${e.unidad}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cardMovimientosPorAlmacen(List<MovimientoReciente> movimientos) {
    final porAlmacen = <String, int>{};
    for (final m in movimientos) {
      porAlmacen[m.almacenId] = (porAlmacen[m.almacenId] ?? 0) + 1;
    }
    final ids = porAlmacen.keys.toList();
    final total = porAlmacen.values.fold<int>(0, (a, b) => a + b);

    return Container(
      width: 340,
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Movimientos por almacén',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ids.isEmpty
                ? const Center(
                    child: Text('Sin movimientos registrados todavía.',
                        style: TextStyle(color: Colors.black54)))
                : PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 34,
                      sections: [
                        for (final id in ids)
                          PieChartSectionData(
                            value: porAlmacen[id]!.toDouble(),
                            color: _colorDe(id),
                            radius: 70,
                            title: total > 0
                                ? '${(porAlmacen[id]! / total * 100).toStringAsFixed(0)}%'
                                : '',
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                      ],
                    ),
                  ),
          ),
          if (ids.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 4, children: [
              for (final id in ids)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, color: _colorDe(id)),
                  const SizedBox(width: 4),
                  Text(id, style: const TextStyle(fontSize: 11)),
                ]),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _cardMermas(List<ResumenMermaArea> porArea, int conAlerta) {
    final hayAlerta = conAlerta > 0;
    final colorEstado = porArea.isEmpty
        ? Colors.black38
        : SemaforoStock.color(
            hayAlerta ? EstadoStock.critico : EstadoStock.optimo);
    final maxY = porArea.isEmpty
        ? 5.0
        : [5.0, ...porArea.map((m) => m.porcentajePromedio * 1.3)]
            .reduce((a, b) => a > b ? a : b);

    return Container(
      width: 340,
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.delete_outline, color: colorEstado, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Mermas por área',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (porArea.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: colorEstado.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      hayAlerta ? '$conAlerta con alerta' : 'Bajo control',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorEstado)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              '% de merma promedio sobre lo producido; en rojo, lo que superó el 3 %.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 12),
          Expanded(
            child: porArea.isEmpty
                ? const Center(
                    child: Text('Sin mermas registradas todavía.',
                        style: TextStyle(color: Colors.black54)))
                : BarChart(
                    BarChartData(
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      gridData:
                          const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}%',
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.black45)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= porArea.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(_etiquetaArea(porArea[i].area),
                                    style: const TextStyle(fontSize: 10)),
                              );
                            },
                          ),
                        ),
                      ),
                      extraLinesData: ExtraLinesData(horizontalLines: [
                        HorizontalLine(
                          y: 3,
                          color: Colors.black38,
                          strokeWidth: 1,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                                fontSize: 9, color: Colors.black45),
                            labelResolver: (_) => '3 %',
                          ),
                        ),
                      ]),
                      barGroups: [
                        for (var i = 0; i < porArea.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: porArea[i].porcentajePromedio,
                              width: 26,
                              borderRadius: BorderRadius.circular(4),
                              color: SemaforoStock.color(porArea[i].alerta
                                  ? EstadoStock.critico
                                  : EstadoStock.optimo),
                            ),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cardPlanDelDia(PlanProduccion plan) {
    final onAbrir = widget.onAbrirProduccion;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAbrir,
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.factory_outlined, color: AppColors.primario),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Plan de producción de hoy',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (onAbrir != null)
                    TextButton(
                        onPressed: onAbrir, child: const Text('Ver todo →')),
                ],
              ),
              const SizedBox(height: 8),
              if (plan.detalle.isEmpty)
                const Text('El Jefe de Producción aún no planificó el día.',
                    style: TextStyle(color: Colors.black54))
              else
                ...plan.detalle.map((d) => ListTile(
                      dense: true,
                      leading: Icon(
                          d.completado
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: d.completado ? Colors.green : Colors.grey),
                      title: Text(d.nombreProducto ?? d.sabor),
                      trailing:
                          Text('${d.litrosPlanificados.toStringAsFixed(0)} L'),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardEnRiesgo(List<ExistenciaItem> criticos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Ítems en riesgo de desabastecimiento',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (criticos.isEmpty)
            const Text('No hay ítems críticos por el momento. 🎉',
                style: TextStyle(color: Colors.black54))
          else
            ...criticos.map((e) => ListTile(
                  dense: true,
                  leading: Icon(_iconoDe(e.almacenId),
                      size: 18, color: _colorDe(e.almacenId)),
                  title: Text(e.detalle),
                  subtitle: Text(
                      '${e.codigo} · ${fmtNum(e.diasExistencia, decimales: 1)} días de existencia'),
                  trailing: Text(
                      '${fmtNum(e.cantidadSistema, decimales: 0)} ${e.unidad}'),
                )),
        ],
      ),
    );
  }

  Widget _cardMovimientosRecientes(List<MovimientoReciente> movimientos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.swap_vert, color: AppColors.primario),
              SizedBox(width: 8),
              Expanded(
                child: Text('Movimientos recientes',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              'Para deshacer un movimiento manual, entrá al ítem desde Almacenes.',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 8),
          if (movimientos.isEmpty)
            const Text('Todavía no hay movimientos registrados.',
                style: TextStyle(color: Colors.black54))
          else
            ...movimientos.map((m) {
              final esIngreso = m.tipo == 'entrada';
              return ListTile(
                dense: true,
                leading: Icon(
                    esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                    color: esIngreso ? Colors.green : Colors.orange,
                    size: 18),
                title: Text(m.itemDetalle),
                subtitle: Text('${fmtFechaHora(m.fecha)} · ${m.almacenId}'
                    '${m.motivo == null ? '' : ' · ${m.motivo}'}'),
                trailing: Text(
                    '${esIngreso ? '+' : ''}${fmtNum(m.cantidad, decimales: 0)} ${m.unidad}'),
              );
            }),
        ],
      ),
    );
  }
}
