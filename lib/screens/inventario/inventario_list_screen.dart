import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/stock_status_badge.dart';
import 'insumo_form_dialog.dart';
import 'movimiento_form_dialog.dart';

class InventarioListScreen extends StatefulWidget {
  const InventarioListScreen({super.key});
  @override
  State<InventarioListScreen> createState() => _InventarioListScreenState();
}

class _InventarioListScreenState extends State<InventarioListScreen> {
  String _tabla = 'tapas';
  String _busqueda = '';
  List<Insumo> _items = [];
  bool _cargando = true;

  final _tabs = const [
    {'v': 'tapas', 'l': 'Tapas'},
    {'v': 'preformas', 'l': 'Preformas'},
    {'v': 'materia_prima', 'l': 'Materia Prima'},
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await InventarioService.listar(_tabla);
    if (!mounted) return;
    setState(() {
      _items = data;
      _cargando = false;
    });
  }

  List<Insumo> get _filtrados => _items
      .where((i) =>
          _busqueda.isEmpty ||
          i.detalle.toLowerCase().contains(_busqueda.toLowerCase()) ||
          i.codigo.toLowerCase().contains(_busqueda.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Inventario',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (usuario.puedeEditarCatalogo) ...[
                OutlinedButton.icon(
                  onPressed: () => _abrirFormularioMovimiento(usuario.id),
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Registrar movimiento'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primario),
                  onPressed: () => _abrirFormularioInsumo(usuario.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo ítem'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ..._tabs.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t['l']!),
                      selected: _tabla == t['v'],
                      onSelected: (_) {
                        setState(() => _tabla = t['v']!);
                        _cargar();
                      },
                    ),
                  )),
              const SizedBox(width: 24),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nombre o código...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _tabla == 'materia_prima'
                    ? _tablaMateriaPrima(usuario)
                    : _tablaTapasPreformas(usuario),
          ),
        ],
      ),
    );
  }

  Widget _tablaTapasPreformas(usuario) {
    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Código')),
          DataColumn(label: Text('Detalle')),
          DataColumn(label: Text('Formato')),
          DataColumn(label: Text('Color/Tamaño')),
          DataColumn(label: Text('Stock real')),
          DataColumn(label: Text('Cajas')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('')),
        ],
        rows: _filtrados
            .map((i) => DataRow(cells: [
                  DataCell(Text(i.codigo)),
                  DataCell(Text(i.detalle)),
                  DataCell(Text(i.formato ?? '-')),
                  DataCell(Text(i.color ?? i.tamano ?? '-')),
                  DataCell(Text('${fmtNum(i.cantidadReal, decimales: 0)} ${i.unidadMedida}')),
                  DataCell(Text(fmtNum(i.cantidadCajas ?? 0, decimales: 1))),
                  DataCell(StockStatusBadge(diasExistencia: i.diasExistencia)),
                  DataCell(_accionesFila(i, usuario)),
                ]))
            .toList(),
      ),
    );
  }

  Widget _tablaMateriaPrima(usuario) {
    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Código')),
          DataColumn(label: Text('Detalle')),
          DataColumn(label: Text('Stock real')),
          DataColumn(label: Text('Consumo/día')),
          DataColumn(label: Text('Días est.')),
          DataColumn(label: Text('Proveedor')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('')),
        ],
        rows: _filtrados
            .map((i) => DataRow(cells: [
                  DataCell(Text(i.codigo)),
                  DataCell(Text(i.detalle)),
                  DataCell(
                      Text('${fmtNum(i.cantidadReal)} ${i.unidadMedida}')),
                  DataCell(Text(fmtNum(i.consumoPromedioDia))),
                  DataCell(Text(
                      i.diasExistencia >= 999 ? '-' : fmtNum(i.diasExistencia, decimales: 1))),
                  DataCell(Text(i.proveedorHabitual ?? '-')),
                  DataCell(StockStatusBadge(diasExistencia: i.diasExistencia)),
                  DataCell(_accionesFila(i, usuario)),
                ]))
            .toList(),
      ),
    );
  }

  Widget _accionesFila(Insumo i, usuario) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (usuario.puedeEditarCatalogo)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _abrirFormularioInsumo(usuario.id, insumo: i),
          ),
        if (usuario.puedeEliminar)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _confirmarEliminar(i, usuario.id),
          ),
      ],
    );
  }

  Future<void> _abrirFormularioInsumo(String usuarioId, {Insumo? insumo}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => InsumoFormDialog(
          tabla: _tabla, insumo: insumo, usuarioId: usuarioId),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _abrirFormularioMovimiento(String usuarioId) async {
    final registrado = await showDialog<bool>(
      context: context,
      builder: (_) => MovimientoFormDialog(
          items: _items, tabla: _tabla, usuarioId: usuarioId),
    );
    if (registrado == true) _cargar();
  }

  Future<void> _confirmarEliminar(Insumo i, String usuarioId) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ítem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${i.detalle}" no se borrará físicamente: quedará marcado '
                'como inactivo y registrado en la bitácora de eliminaciones.'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      await InventarioService.eliminar(
          i.tabla, i.id, usuarioId, motivoCtrl.text);
      _cargar();
    }
  }
}
