import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/soda_modelos.dart';
import '../services/soda_service.dart';

/// Registra una entrega de Soda Cáustica: ítem, cantidad, a quién se le
/// entrega, área (opcional) y motivo o uso (opcional). El saldo restante lo
/// calcula el servidor.
class RegistrarEntregaDialog extends StatefulWidget {
  final SodaService servicio;
  const RegistrarEntregaDialog({super.key, required this.servicio});

  @override
  State<RegistrarEntregaDialog> createState() => _RegistrarEntregaDialogState();
}

class _RegistrarEntregaDialogState extends State<RegistrarEntregaDialog> {
  ItemInventario? _item;
  final _cantidad = TextEditingController();
  final _entregadoA = TextEditingController();
  final _area = TextEditingController();
  final _motivo = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _cantidad.dispose();
    _entregadoA.dispose();
    _area.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final t = _cantidad.text.trim().replaceAll(',', '.');
    final error = await widget.servicio.registrarEntrega(
      item: _item,
      cantidad: t.isEmpty ? null : double.tryParse(t),
      entregadoA: _entregadoA.text,
      areaRecibe: _area.text,
      motivo: _motivo.text,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Entrega registrada.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label, {String? ayuda}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final svc = widget.servicio;

    return ModalFormulario(
      titulo: 'Registrar entrega',
      icono: Icons.warning_amber_rounded,
      textoBoton: 'Registrar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Autocomplete<ItemInventario>(
            displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
            optionsBuilder: (t) => svc.buscarItems(t.text),
            onSelected: (i) => setState(() => _item = i),
            fieldViewBuilder: (context, c, foco, _) => TextField(
              controller: c,
              focusNode: foco,
              onChanged: (t) {
                if (_item != null && t != '${_item!.codigo} · ${_item!.detalle}') _item = null;
              },
              decoration: _deco('Producto', ayuda: 'Buscá "soda cáustica" u otro ítem'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _cantidad,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Cantidad${_item == null ? '' : ' (${_item!.unidad})'}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _entregadoA,
                  decoration: _deco('Entregado a (persona)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _area, decoration: _deco('Área que recibe (opcional)')),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            maxLength: 300,
            maxLines: 2,
            decoration: _deco('Motivo o uso (opcional)').copyWith(counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }
}
