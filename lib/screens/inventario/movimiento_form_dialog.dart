import 'package:flutter/material.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../services/inventario_service.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../widgets/autocompletar_texto.dart';

/// Registrar entrada/salida/ajuste. Cumple el caso de uso 1 y 2:
/// selecciona el insumo, cantidad, lote, vencimiento, proveedor; si no
/// hay internet igual se guarda (queda en la cola de sincronización).
///
/// El buscador de insumo es solo para ENCONTRAR un ítem ya existente
/// (no se puede crear uno nuevo desde acá, a propósito: mezclar "buscar"
/// con "crear" en el mismo campo es lo que hace fácil equivocarse de
/// ítem sin darse cuenta). Para dar de alta un insumo nuevo se usa el
/// botón "Nuevo ítem" de la pantalla de Inventario.
class MovimientoFormDialog extends StatefulWidget {
  final List<Insumo> items;
  final String tabla;
  final String usuarioId;
  const MovimientoFormDialog(
      {super.key,
      required this.items,
      required this.tabla,
      required this.usuarioId});

  @override
  State<MovimientoFormDialog> createState() => _MovimientoFormDialogState();
}

class _MovimientoFormDialogState extends State<MovimientoFormDialog> {
  Insumo? _seleccionado;
  String _tipo = 'ingreso';
  final _cantidadCtrl = TextEditingController();
  final _loteCtrl = TextEditingController();
  String _proveedor = '';
  final _observacionCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  DateTime? _vencimiento;
  bool _guardando = false;
  List<String> _proveedores = [];

  @override
  void initState() {
    super.initState();
    InventarioService.listarProveedores().then((lista) {
      if (mounted) setState(() => _proveedores = lista);
    });
  }

  Future<void> _guardar() async {
    if (_seleccionado == null || _cantidadCtrl.text.isEmpty) return;
    setState(() => _guardando = true);

    final mov = Movimiento(
      tablaOrigen: _seleccionado!.tabla,
      itemId: _seleccionado!.id,
      tipo: _tipo,
      cantidad: double.tryParse(_cantidadCtrl.text) ?? 0,
      unidadMedida: _seleccionado!.unidadMedida,
      lote: _loteCtrl.text.isEmpty ? null : _loteCtrl.text,
      fechaVencimiento: _vencimiento,
      proveedor: _proveedor.trim().isEmpty ? null : _proveedor.trim(),
      observacion:
          _observacionCtrl.text.isEmpty ? null : _observacionCtrl.text,
      usuarioId: widget.usuarioId,
      creadoEn: _fecha,
    );

    final enviadoDirecto = await InventarioService.registrarMovimiento(mov);
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(enviadoDirecto
            ? 'Movimiento registrado.'
            : 'Sin conexión: guardado localmente. Se sincronizará automáticamente.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar movimiento'),
      content: SizedBox(
        width: anchoDialogo(context, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Autocomplete<Insumo>(
                displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return widget.items;
                  return widget.items.where((i) =>
                      i.detalle.toLowerCase().contains(q) ||
                      i.codigo.toLowerCase().contains(q));
                },
                onSelected: (i) => setState(() {
                  _seleccionado = i;
                  // Autocompleta con el dato ya conocido del insumo, pero
                  // sigue siendo un campo editable por si corresponde otro
                  // proveedor puntual para esta entrada.
                  if (_tipo == 'ingreso' &&
                      i.proveedorHabitual != null &&
                      i.proveedorHabitual!.isNotEmpty) {
                    _proveedor = i.proveedorHabitual!;
                  }
                }),
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (_) => setState(() => _seleccionado = null),
                    decoration: const InputDecoration(
                      labelText: 'Insumo *',
                      hintText: 'Buscar por código o nombre...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  );
                },
              ),
              if (_seleccionado == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    'Elegí un ítem de la lista de resultados (si no existe, '
                    'creálo primero desde "Nuevo ítem" en Inventario).',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ingreso', label: Text('Entrada')),
                      ButtonSegment(value: 'salida', label: Text('Salida')),
                      ButtonSegment(value: 'ajuste', label: Text('Ajuste')),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (s) => setState(() => _tipo = s.first),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cantidadCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Cantidad *',
                  helperText: _seleccionado != null
                      ? 'Stock actual: ${fmtNum(_seleccionado!.cantidadReal, decimales: 0)} ${_seleccionado!.unidadMedida}'
                      : null,
                ),
              ),
              TextField(
                controller: _loteCtrl,
                decoration: const InputDecoration(labelText: 'Lote'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.today, size: 18),
                title: Text('Fecha: ${fmtFecha(_fecha)}'),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final f = await showDatePicker(
                    context: context,
                    initialDate: _fecha,
                    firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                    lastDate: DateTime.now(),
                  );
                  if (f != null) {
                    setState(() => _fecha = DateTime(
                        f.year, f.month, f.day, _fecha.hour, _fecha.minute));
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_vencimiento == null
                    ? 'Fecha de vencimiento (opcional)'
                    : 'Vence: ${fmtFecha(_vencimiento)}'),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final f = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (f != null) setState(() => _vencimiento = f);
                },
              ),
              if (_tipo == 'ingreso')
                AutocompletarTexto(
                  // Al cambiar de insumo, se recrea con el proveedor
                  // habitual como valor inicial (sigue siendo editable).
                  key: ValueKey('proveedor-${_seleccionado?.id}'),
                  label: 'Proveedor',
                  valorInicial: _proveedor,
                  opciones: _proveedores,
                  onChanged: (v) => _proveedor = v,
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _observacionCtrl,
                decoration: const InputDecoration(labelText: 'Observación'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Registrar'),
        ),
      ],
    );
  }
}
