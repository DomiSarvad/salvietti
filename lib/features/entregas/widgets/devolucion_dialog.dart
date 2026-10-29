import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import '../../../utils/formatters.dart';
import '../models/entregas_modelos.dart';
import '../services/entregas_service.dart';

/// Registra la devolución de lo que sobró de una línea ya entregada.
class DevolucionDialog extends StatefulWidget {
  final EntregasService servicio;
  final Pedido pedido;
  final LineaPedido linea;
  const DevolucionDialog(
      {super.key, required this.servicio, required this.pedido, required this.linea});

  @override
  State<DevolucionDialog> createState() => _DevolucionDialogState();
}

class _DevolucionDialogState extends State<DevolucionDialog> {
  // Precargado SIN separador de miles (es un campo para editar, no para leer):
  // "1.000,000" no lo entendería la lectura de abajo.
  late final _cantidad = TextEditingController(
      text: widget.linea.disponibleParaDevolver
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'\.?0+$'), '')
          .replaceAll('.', ','));
  final _motivo = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _cantidad.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final t = _cantidad.text.trim().replaceAll(',', '.');
    final error = await widget.servicio.registrarDevolucion(
        widget.pedido, widget.linea, t.isEmpty ? null : double.tryParse(t), _motivo.text);
    if (!mounted) return;
    if (error == null) {
      avisoExito(context, 'Devolución registrada');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linea;
    return AlertDialog(
      title: Text('Devolver "${l.detalle}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disponible para devolver: ${fmtNum(l.disponibleParaDevolver, decimales: 3)} ${l.unidad}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          TextField(
            controller: _cantidad,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Cantidad a devolver (${l.unidad})'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _motivo,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo (opcional)', counterText: ''),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Devolver'),
        ),
      ],
    );
  }
}
