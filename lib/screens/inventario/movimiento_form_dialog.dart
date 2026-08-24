import 'package:flutter/material.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../services/inventario_service.dart';

/// Registrar entrada/salida/ajuste. Cumple el caso de uso 1 y 2:
/// selecciona el insumo, cantidad, lote, vencimiento, proveedor; si no
/// hay internet igual se guarda (queda en la cola de sincronización).
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
  final _proveedorCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();
  DateTime? _vencimiento;
  bool _guardando = false;

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
      proveedor: _proveedorCtrl.text.isEmpty ? null : _proveedorCtrl.text,
      observacion:
          _observacionCtrl.text.isEmpty ? null : _observacionCtrl.text,
      usuarioId: widget.usuarioId,
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
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Insumo>(
                decoration: const InputDecoration(labelText: 'Insumo *'),
                items: widget.items
                    .map((i) => DropdownMenuItem(
                        value: i, child: Text('${i.codigo} · ${i.detalle}')))
                    .toList(),
                onChanged: (v) => setState(() => _seleccionado = v),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ingreso', label: Text('Entrada')),
                  ButtonSegment(value: 'salida', label: Text('Salida')),
                  ButtonSegment(value: 'ajuste', label: Text('Ajuste')),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cantidadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad *'),
              ),
              TextField(
                controller: _loteCtrl,
                decoration: const InputDecoration(labelText: 'Lote'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_vencimiento == null
                    ? 'Fecha de vencimiento (opcional)'
                    : 'Vence: ${_vencimiento!.day}/${_vencimiento!.month}/${_vencimiento!.year}'),
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
                TextField(
                  controller: _proveedorCtrl,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                ),
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
