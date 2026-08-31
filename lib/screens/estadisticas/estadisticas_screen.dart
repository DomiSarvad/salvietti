import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../services/movimiento_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/stock_status_badge.dart';

/// Contenido distinto según el rol: Jarabes ve el estado de su propia
/// área; Gerente/Ingeniero/Almacén ven el gráfico de producción de toda
/// la planta.
class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});
  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  DateTimeRange _rango = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now());
  bool _cargando = true;
  String _tipoGrafico = 'barras'; // 'barras' | 'lineas' | 'torta'

  static const _paletaSabores = [
    AppColors.primario,
    AppColors.secundario,
    Color(0xFF2563EB),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
    Color(0xFFDB2777),
  ];

  // Jarabes
  List<Insumo> _insumosJarabes = [];
  List<Movimiento> _consumoJarabes = [];

  // Gerente / Ingeniero / Almacén
  Map<String, double> _litrosPorSabor = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final usuario = context.read<AuthService>().usuarioActual!;

    if (usuario.esJarabes) {
      final insumos = await InventarioService.listar('materia_prima');
      final jarabes = insumos.where((i) => i.area == 'jarabes').toList();
      final movimientos = await MovimientoService.listarPorFiltro(
          desde: _rango.start, hasta: _rango.end, tabla: 'materia_prima');
      final idsJarabes = jarabes.map((i) => i.id).toSet();
      if (!mounted) return;
      setState(() {
        _insumosJarabes = jarabes;
        _consumoJarabes = movimientos
            .where((m) => m.tipo == 'salida' && idsJarabes.contains(m.itemId))
            .toList();
        _cargando = false;
      });
    } else {
      final historial = await ProduccionService.historialProduccion(
          desde: _rango.start, hasta: _rango.end);
      final litrosPorSabor = <String, double>{};
      for (final fila in historial) {
        final sabor = fila['formulas']?['sabor'] ?? 'Sin sabor';
        final litros = (fila['litros_producidos'] as num?)?.toDouble() ?? 0;
        litrosPorSabor[sabor] = (litrosPorSabor[sabor] ?? 0) + litros;
      }
      if (!mounted) return;
      setState(() {
        _litrosPorSabor = litrosPorSabor;
        _cargando = false;
      });
    }
  }

  Future<void> _elegirRango() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _rango,
    );
    if (rango != null) {
      setState(() => _rango = rango);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estadísticas',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Wrap: en pantallas angostas el botón de fecha (con un texto
          // largo) pasa a su propia línea en vez de desbordar.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _elegirRango,
                icon: const Icon(Icons.date_range),
                label: Text(
                    '${fmtFecha(_rango.start)} - ${fmtFecha(_rango.end)}'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : usuario.esJarabes
                    ? _contenidoJarabes()
                    : _contenidoProduccion(),
          ),
        ],
      ),
    );
  }

  Widget _contenidoJarabes() {
    final criticos =
        _insumosJarabes.where((i) => i.diasExistencia <= 3).length;
    final bajos = _insumosJarabes
        .where((i) => i.diasExistencia > 3 && i.diasExistencia <= 7)
        .length;
    final optimos = _insumosJarabes.length - criticos - bajos;

    return ListView(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _tarjeta('Óptimos', optimos, Colors.green),
            _tarjeta('Bajos', bajos, Colors.orange),
            _tarjeta('Críticos', criticos, Colors.red),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Estado de tus insumos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._insumosJarabes.map((i) => Card(
              child: ListTile(
                title: Text(i.detalle),
                subtitle: Text(
                    '${fmtNum(i.cantidadReal, decimales: 0)} ${i.unidadMedida}'),
                trailing: StockStatusBadge(diasExistencia: i.diasExistencia),
              ),
            )),
        const SizedBox(height: 24),
        const Text('Consumo reciente',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_consumoJarabes.isEmpty)
          const Text('Sin salidas registradas en el rango elegido.',
              style: TextStyle(color: Colors.black54))
        else
          ..._consumoJarabes.map((m) {
            final item =
                _insumosJarabes.where((i) => i.id == m.itemId).toList();
            return ListTile(
              dense: true,
              title: Text(item.isNotEmpty ? item.first.detalle : m.itemId),
              subtitle: Text(fmtFechaHora(m.creadoEn)),
              trailing: Text('-${fmtNum(m.cantidad, decimales: 0)} ${m.unidadMedida ?? ''}'),
            );
          }),
      ],
    );
  }

  Widget _contenidoProduccion() {
    if (_litrosPorSabor.isEmpty) {
      return const Center(
          child: Text('No hay producción completada en el rango elegido.'));
    }
    final sabores = _litrosPorSabor.keys.toList();
    final maxY = _litrosPorSabor.values.reduce((a, b) => a > b ? a : b) * 1.2;
    final totalLitros = _litrosPorSabor.values.fold<double>(0, (a, b) => a + b);

    return ListView(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _tarjeta('Litros producidos', totalLitros.round(), AppColors.primario),
            _tarjeta('Sabores distintos', sabores.length, AppColors.secundario),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Litros producidos por sabor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // Envuelto en scroll horizontal: en celular, un SegmentedButton de
        // 3 opciones con íconos no siempre entra en el ancho de pantalla.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'barras',
                    icon: Icon(Icons.bar_chart, size: 18),
                    label: Text('Barras')),
                ButtonSegment(
                    value: 'lineas',
                    icon: Icon(Icons.show_chart, size: 18),
                    label: Text('Líneas')),
                ButtonSegment(
                    value: 'torta',
                    icon: Icon(Icons.pie_chart_outline, size: 18),
                    label: Text('Torta')),
              ],
              selected: {_tipoGrafico},
              onSelectionChanged: (s) => setState(() => _tipoGrafico = s.first),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 340,
          child: switch (_tipoGrafico) {
            'lineas' => _graficoLineas(sabores, maxY),
            'torta' => _graficoTorta(sabores, totalLitros),
            _ => _graficoBarras(sabores, maxY),
          },
        ),
      ],
    );
  }

  Widget _tituloEjeX(double value, List<String> sabores) {
    final i = value.toInt();
    if (i < 0 || i >= sabores.length) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(sabores[i], style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _graficoBarras(List<String> sabores, double maxY) {
    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        barGroups: [
          for (int i = 0; i < sabores.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                  toY: _litrosPorSabor[sabores[i]]!,
                  color: _paletaSabores[i % _paletaSabores.length],
                  width: 22,
                  borderRadius: BorderRadius.circular(4)),
            ]),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => _tituloEjeX(value, sabores),
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }

  Widget _graficoLineas(List<String> sabores, double maxY) {
    return LineChart(
      LineChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < sabores.length; i++)
                FlSpot(i.toDouble(), _litrosPorSabor[sabores[i]]!),
            ],
            isCurved: true,
            color: AppColors.primario,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
                show: true, color: AppColors.primario.withOpacity(0.12)),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => _tituloEjeX(value, sabores),
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }

  Widget _graficoTorta(List<String> sabores, double totalLitros) {
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (int i = 0; i < sabores.length; i++)
                  PieChartSectionData(
                    value: _litrosPorSabor[sabores[i]],
                    color: _paletaSabores[i % _paletaSabores.length],
                    radius: 90,
                    title: totalLitros > 0
                        ? '${(_litrosPorSabor[sabores[i]]! / totalLitros * 100).toStringAsFixed(0)}%'
                        : '',
                    titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < sabores.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: _paletaSabores[i % _paletaSabores.length],
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(sabores[i], style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tarjeta(String titulo, int valor, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 8),
          Text('$valor',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
