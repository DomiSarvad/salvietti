import 'package:flutter/material.dart';
import '../../models/insumo.dart';
import '../../services/inventario_service.dart';

/// Formulario de alta/edición. El código (IN-xxx / MP-xxx) se genera
/// automáticamente en el servidor — el usuario nunca lo escribe a mano,
/// cumpliendo el requisito de "procesos automáticos como los códigos".
class InsumoFormDialog extends StatefulWidget {
  final String tabla;
  final Insumo? insumo;
  final String usuarioId;
  const InsumoFormDialog(
      {super.key, required this.tabla, this.insumo, required this.usuarioId});

  @override
  State<InsumoFormDialog> createState() => _InsumoFormDialogState();
}

class _InsumoFormDialogState extends State<InsumoFormDialog> {
  final _detalleCtrl = TextEditingController();
  final _formatoCtrl = TextEditingController();
  final _colorTamanoCtrl = TextEditingController();
  final _unidadCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController();
  final _stockMinCtrl = TextEditingController();
  final _proveedorCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final i = widget.insumo;
    if (i != null) {
      _detalleCtrl.text = i.detalle;
      _formatoCtrl.text = i.formato ?? '';
      _colorTamanoCtrl.text = i.color ?? i.tamano ?? '';
      _unidadCtrl.text = i.unidadMedida;
      _cantidadCtrl.text = i.cantidadReal.toString();
      _stockMinCtrl.text = i.stockMinimo.toString();
      _proveedorCtrl.text = i.proveedorHabitual ?? '';
    } else {
      _unidadCtrl.text = widget.tabla == 'materia_prima' ? 'KG' : 'PZA';
    }
  }

  Future<void> _guardar() async {
    if (_detalleCtrl.text.trim().isEmpty) return;
    setState(() => _guardando = true);

    final insumo = Insumo(
      id: widget.insumo?.id ?? '',
      tabla: widget.tabla,
      codigo: widget.insumo?.codigo ?? '', // se autogenera si está vacío
      detalle: _detalleCtrl.text.trim(),
      formato: widget.tabla != 'materia_prima' ? _formatoCtrl.text : null,
      color: widget.tabla == 'tapas' ? _colorTamanoCtrl.text : null,
      tamano: widget.tabla == 'preformas' ? _colorTamanoCtrl.text : null,
      unidadMedida: _unidadCtrl.text.trim(),
      cantidadSistema: widget.insumo?.cantidadSistema ??
          double.tryParse(_cantidadCtrl.text) ??
          0,
      cantidadReal: double.tryParse(_cantidadCtrl.text) ?? 0,
      stockMinimo: double.tryParse(_stockMinCtrl.text) ?? 0,
      proveedorHabitual:
          widget.tabla == 'materia_prima' ? _proveedorCtrl.text : null,
    );

    try {
      if (widget.insumo == null) {
        await InventarioService.crear(insumo, widget.usuarioId);
      } else {
        await InventarioService.actualizar(insumo, widget.usuarioId);
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esMP = widget.tabla == 'materia_prima';
    return AlertDialog(
      title: Text(widget.insumo == null ? 'Nuevo ítem' : 'Editar ítem'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _detalleCtrl,
                decoration: const InputDecoration(labelText: 'Detalle *'),
              ),
              if (!esMP)
                TextField(
                  controller: _formatoCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Formato (Short/Long Finish...)'),
                ),
              TextField(
                controller: _colorTamanoCtrl,
                decoration: InputDecoration(
                    label: Text(widget.tabla == 'tapas'
                        ? 'Color'
                        : widget.tabla == 'preformas'
                            ? 'Tamaño (ej. 2,5 L)'
                            : '')),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _unidadCtrl,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cantidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Cantidad real'),
                  ),
                ),
              ]),
              TextField(
                controller: _stockMinCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Stock mínimo (alerta)'),
              ),
              if (esMP)
                TextField(
                  controller: _proveedorCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Proveedor habitual'),
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
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
