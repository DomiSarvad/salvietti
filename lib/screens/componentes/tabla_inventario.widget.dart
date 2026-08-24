import 'package:flutter/material.dart';

import '../../models/insumo_model.dart';

enum _FiltroEstado { todos, critico, observacion, seguro }

class TablaInventarioWidget extends StatefulWidget {
  final List<InsumoModel> insumos;
  final bool canDelete;
  final void Function(InsumoModel insumo)? onDelete;
  final void Function(InsumoModel insumo)? onTap;

  const TablaInventarioWidget({
    super.key,
    required this.insumos,
    this.canDelete = false,
    this.onDelete,
    this.onTap,
  });

  @override
  State<TablaInventarioWidget> createState() => _TablaInventarioWidgetState();
}

class _TablaInventarioWidgetState extends State<TablaInventarioWidget> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  _FiltroEstado _filtro = _FiltroEstado.todos;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Color _colorEstado(StockNivel nivel) {
    switch (nivel) {
      case StockNivel.critico:
        return Colors.red.shade700;
      case StockNivel.observacion:
        return Colors.orange.shade800;
      case StockNivel.seguro:
        return Colors.green.shade800;
    }
  }

  String _labelEstado(StockNivel nivel) {
    switch (nivel) {
      case StockNivel.critico:
        return 'CRÍTICO';
      case StockNivel.observacion:
        return 'BAJO';
      case StockNivel.seguro:
        return 'ÓPTIMO';
    }
  }

  List<InsumoModel> get _filtrados {
    final texto = _busqueda.trim().toLowerCase();
    return widget.insumos.where((insumo) {
      final coincideTexto = texto.isEmpty ||
          insumo.nombre.toLowerCase().contains(texto) ||
          insumo.numeroLote.toLowerCase().contains(texto) ||
          insumo.proveedorNombre.toLowerCase().contains(texto);

      final coincideFiltro = switch (_filtro) {
        _FiltroEstado.todos => true,
        _FiltroEstado.critico => insumo.nivelStock == StockNivel.critico,
        _FiltroEstado.observacion =>
          insumo.nivelStock == StockNivel.observacion,
        _FiltroEstado.seguro => insumo.nivelStock == StockNivel.seguro,
      };

      return coincideTexto && coincideFiltro;
    }).toList()
      ..sort((a, b) {
        int rango(InsumoModel i) => switch (i.nivelStock) {
          StockNivel.critico => 0,
          StockNivel.observacion => 1,
          StockNivel.seguro => 2,
        };
        final cmp = rango(a).compareTo(rango(b));
        if (cmp != 0) return cmp;
        return a.nombre.compareTo(b.nombre);
      });
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _busquedaController,
                  onChanged: (value) => setState(() => _busqueda = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar por insumo, lote o proveedor...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _filtroChip('Todos', _FiltroEstado.todos),
              _filtroChip('Crítico', _FiltroEstado.critico),
              _filtroChip('Observación', _FiltroEstado.observacion),
              _filtroChip('Seguro', _FiltroEstado.seguro),
              const Spacer(),
              Text(
                'Mostrando ${filtrados.length} de ${widget.insumos.length} insumos',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtrados.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No hay insumos que coincidan con la búsqueda.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                columnSpacing: 28,
                columns: const [
                  DataColumn(label: Text('INSUMO')),
                  DataColumn(label: Text('LOTE')),
                  DataColumn(label: Text('STOCK'), numeric: true),
                  DataColumn(label: Text('CONSUMO/DÍA'), numeric: true),
                  DataColumn(label: Text('DÍAS EST.'), numeric: true),
                  DataColumn(label: Text('ESTADO')),
                  DataColumn(label: Text('')),
                ],
                rows: filtrados.map((insumo) {
                  final color = _colorEstado(insumo.nivelStock);
                  final dias = insumo.diasRestantesStock;
                  return DataRow(
                    onSelectChanged: widget.onTap == null
                        ? null
                        : (_) => widget.onTap!(insumo),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            insumo.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataCell(Text(insumo.numeroLote)),
                      DataCell(
                        Text(
                          '${insumo.stockActual.toStringAsFixed(1)} ${insumo.unidadMedida}',
                        ),
                      ),
                      DataCell(
                        Text(
                          insumo.consumoDiarioPromedio > 0
                              ? insumo.consumoDiarioPromedio.toStringAsFixed(1)
                              : '-',
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dias.isFinite ? dias.toStringAsFixed(1) : '—',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _labelEstado(insumo.nivelStock),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        widget.canDelete
                            ? IconButton(
                                tooltip: 'Borrado lógico',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade400,
                                  size: 20,
                                ),
                                onPressed: () => widget.onDelete?.call(insumo),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filtroChip(String label, _FiltroEstado valor) {
    final seleccionado = _filtro == valor;
    return ChoiceChip(
      label: Text(label),
      selected: seleccionado,
      onSelected: (_) => setState(() => _filtro = valor),
      selectedColor: Colors.green.shade700,
      labelStyle: TextStyle(
        color: seleccionado ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
    );
  }
}
