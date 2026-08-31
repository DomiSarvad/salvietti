import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../services/movimiento_service.dart';
import '../../utils/formatters.dart';

const _etiquetaTipo = {
  'ingreso': 'Entrada',
  'salida': 'Salida',
  'ajuste': 'Ajuste',
  'produccion': 'Producción',
};

/// Reportes de movimientos (entradas/salidas) filtrables por fecha y
/// categoría, individuales (un insumo puntual) o grupales (todos los
/// de la categoría elegida), exportables a PDF y Excel. Disponible
/// para todos los roles; Jarabes solo puede reportar su propia área.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});
  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  // Sin fecha por defecto: si no se elige, el reporte no filtra por fecha.
  DateTime? _desde;
  DateTime? _hasta;
  late String _categoria;
  String _modo = 'grupal'; // 'grupal' | 'individual'
  Insumo? _insumoElegido;
  List<Insumo> _insumosCategoria = [];
  final Map<String, Insumo> _insumoPorId = {};
  bool _cargandoInsumos = true;
  bool _generando = false;
  String? _mensaje;

  List<Map<String, String>> _categoriasDisponibles(bool esJarabes) => esJarabes
      ? const [
          {'v': 'jarabes', 'l': 'Materia Prima (Jarabes)'},
        ]
      : const [
          {'v': 'todas', 'l': 'Todas las categorías'},
          {'v': 'tapas', 'l': 'Tapas'},
          {'v': 'preformas', 'l': 'Preformas'},
          {'v': 'materia_prima', 'l': 'Materia Prima'},
          {'v': 'jarabes', 'l': 'Materia Prima (Jarabes)'},
        ];

  @override
  void initState() {
    super.initState();
    final usuario = context.read<AuthService>().usuarioActual!;
    _categoria = usuario.esJarabes ? 'jarabes' : 'todas';
    _cargarInsumos();
  }

  Future<void> _cargarInsumos() async {
    setState(() => _cargandoInsumos = true);
    final usuario = context.read<AuthService>().usuarioActual!;
    final tablas = usuario.esJarabes
        ? ['materia_prima']
        : ['tapas', 'preformas', 'materia_prima'];
    final todos = <Insumo>[];
    for (final t in tablas) {
      todos.addAll(await InventarioService.listar(t, soloActivos: false));
    }
    for (final i in todos) {
      _insumoPorId[i.id] = i;
    }
    if (!mounted) return;
    setState(() {
      _insumosCategoria = _filtrarPorCategoria(todos, _categoria);
      _insumoElegido = _insumosCategoria.isNotEmpty ? _insumosCategoria.first : null;
      _cargandoInsumos = false;
    });
  }

  List<Insumo> _filtrarPorCategoria(List<Insumo> todos, String categoria) {
    switch (categoria) {
      case 'jarabes':
        return todos.where((i) => i.tabla == 'materia_prima' && i.area == 'jarabes').toList();
      case 'todas':
        return todos;
      default:
        return todos.where((i) => i.tabla == categoria).toList();
    }
  }

  Future<void> _elegirDesde() async {
    final fecha = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: _hasta ?? DateTime.now(),
      initialDate: _desde ?? DateTime.now(),
    );
    if (fecha != null) setState(() => _desde = fecha);
  }

  Future<void> _elegirHasta() async {
    final fecha = await showDatePicker(
      context: context,
      firstDate: _desde ?? DateTime(2024),
      lastDate: DateTime.now(),
      initialDate: _hasta ?? DateTime.now(),
    );
    if (fecha != null) setState(() => _hasta = fecha);
  }

  Future<List<Movimiento>> _movimientosDelReporte() async {
    final categoriaTabla = _categoria == 'jarabes' ? 'materia_prima' : _categoria;
    final tabla = categoriaTabla == 'todas' ? null : categoriaTabla;
    final itemId = _modo == 'individual' ? _insumoElegido?.id : null;

    var movimientos = await MovimientoService.listarPorFiltro(
      desde: _desde,
      // +1 día para incluir todo el día "hasta" (la fecha elegida viene a medianoche).
      hasta: _hasta?.add(const Duration(days: 1)),
      tabla: tabla,
      itemId: itemId,
    );
    if (_categoria == 'jarabes') {
      final idsJarabes = _insumosCategoria.map((i) => i.id).toSet();
      movimientos = movimientos.where((m) => idsJarabes.contains(m.itemId)).toList();
    }
    return movimientos;
  }

  String _descripcionRango() {
    if (_desde == null && _hasta == null) return 'Todas las fechas';
    if (_desde != null && _hasta != null) {
      return '${fmtFecha(_desde)} - ${fmtFecha(_hasta)}';
    }
    return _desde != null ? 'Desde ${fmtFecha(_desde)}' : 'Hasta ${fmtFecha(_hasta)}';
  }

  String _nombreInsumo(String itemId) => _insumoPorId[itemId]?.detalle ?? itemId;
  String _codigoInsumo(String itemId) => _insumoPorId[itemId]?.codigo ?? '-';

  Future<void> _generar(bool esPdf) async {
    setState(() {
      _generando = true;
      _mensaje = null;
    });
    try {
      final movimientos = await _movimientosDelReporte();
      if (movimientos.isEmpty) {
        setState(() => _mensaje = 'No hay movimientos en ese rango/categoría.');
        return;
      }
      final titulo = _modo == 'individual' && _insumoElegido != null
          ? 'Reporte de ${_insumoElegido!.detalle}'
          : 'Reporte de movimientos';

      final Uint8List bytes = esPdf
          ? await _construirPdf(titulo, movimientos)
          : Uint8List.fromList(_construirExcel(movimientos));

      await FileSaver.instance.saveAs(
        name: 'reporte_salvietti_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        ext: esPdf ? 'pdf' : 'xlsx',
        mimeType: esPdf ? MimeType.pdf : MimeType.microsoftExcel,
      );
      if (mounted) setState(() => _mensaje = 'Reporte generado correctamente.');
    } catch (e) {
      setState(() => _mensaje = 'No se pudo generar el reporte: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<Uint8List> _construirPdf(String titulo, List<Movimiento> movimientos) async {
    final doc = pw.Document();
    final agrupado = _modo == 'grupal';

    List<List<String>> filasDe(List<Movimiento> lista) => lista
        .map((m) => [
              fmtFechaHora(m.creadoEn),
              _etiquetaTipo[m.tipo] ?? m.tipo,
              fmtNum(m.cantidad, decimales: 0),
              m.unidadMedida ?? '',
            ])
        .toList();

    final widgets = <pw.Widget>[
      pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(_descripcionRango(),
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.SizedBox(height: 16),
    ];

    if (agrupado) {
      final porInsumo = <String, List<Movimiento>>{};
      for (final m in movimientos) {
        porInsumo.putIfAbsent(m.itemId, () => []).add(m);
      }
      for (final entry in porInsumo.entries) {
        final total = entry.value.fold<double>(
            0, (s, m) => s + (m.tipo == 'ingreso' ? m.cantidad : -m.cantidad));
        widgets.addAll([
          pw.Text('${_nombreInsumo(entry.key)} (${_codigoInsumo(entry.key)})',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(
            headers: ['Fecha', 'Tipo', 'Cantidad', 'Unidad'],
            data: filasDe(entry.value),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Neto: ${fmtNum(total, decimales: 0)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
          pw.SizedBox(height: 14),
        ]);
      }
    } else {
      widgets.add(pw.Table.fromTextArray(
        headers: ['Fecha', 'Tipo', 'Cantidad', 'Unidad'],
        data: filasDe(movimientos),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
      ));
    }

    doc.addPage(pw.MultiPage(build: (context) => widgets));
    return doc.save();
  }

  List<int> _construirExcel(List<Movimiento> movimientos) {
    final excel = xls.Excel.createExcel();
    final hoja = excel['Reporte'];
    excel.setDefaultSheet('Reporte');
    hoja.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Código'),
      xls.TextCellValue('Insumo'),
      xls.TextCellValue('Tipo'),
      xls.TextCellValue('Cantidad'),
      xls.TextCellValue('Unidad'),
    ]);
    for (final m in movimientos) {
      hoja.appendRow([
        xls.TextCellValue(fmtFechaHora(m.creadoEn)),
        xls.TextCellValue(_codigoInsumo(m.itemId)),
        xls.TextCellValue(_nombreInsumo(m.itemId)),
        xls.TextCellValue(_etiquetaTipo[m.tipo] ?? m.tipo),
        xls.DoubleCellValue(m.cantidad),
        xls.TextCellValue(m.unidadMedida ?? ''),
      ]);
    }
    return excel.save() ?? [];
  }

  /// Campo de fecha opcional: si no se elige nada, el reporte simplemente
  /// no filtra por esa punta del rango (en vez de exigir una fecha).
  Widget _campoFecha({
    required String etiqueta,
    required DateTime? valor,
    required VoidCallback onElegir,
    required VoidCallback onLimpiar,
  }) {
    return OutlinedButton.icon(
      onPressed: onElegir,
      icon: const Icon(Icons.date_range, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(valor == null ? '$etiqueta: sin elegir' : '$etiqueta: ${fmtFecha(valor)}'),
          if (valor != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onLimpiar,
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;
    final categorias = _categoriasDisponibles(usuario.esJarabes);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reportes',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _campoFecha(
                  etiqueta: 'Desde',
                  valor: _desde,
                  onElegir: _elegirDesde,
                  onLimpiar: () => setState(() => _desde = null)),
              _campoFecha(
                  etiqueta: 'Hasta',
                  valor: _hasta,
                  onElegir: _elegirHasta,
                  onLimpiar: () => setState(() => _hasta = null)),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  value: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: categorias
                      .map((c) => DropdownMenuItem(value: c['v'], child: Text(c['l']!)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _categoria = v!);
                    _cargarInsumos();
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'grupal', label: Text('Grupal')),
                    ButtonSegment(value: 'individual', label: Text('Individual')),
                  ],
                  selected: {_modo},
                  onSelectionChanged: (s) => setState(() => _modo = s.first),
                ),
              ),
              if (_modo == 'individual')
                SizedBox(
                  width: 260,
                  child: _cargandoInsumos
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<Insumo>(
                          value: _insumoElegido,
                          decoration: const InputDecoration(labelText: 'Insumo'),
                          items: _insumosCategoria
                              .map((i) => DropdownMenuItem(
                                  value: i, child: Text('${i.codigo} · ${i.detalle}')))
                              .toList(),
                          onChanged: (v) => setState(() => _insumoElegido = v),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _generando ? null : () => _generar(true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generar PDF'),
              ),
              FilledButton.icon(
                onPressed: _generando ? null : () => _generar(false),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Generar Excel'),
              ),
              if (_generando)
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: 16),
            Text(_mensaje!, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }
}
