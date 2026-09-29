import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/existencia_item.dart';
import '../services/inventario_service.dart';

/// Conteo físico de un ítem: se escribe lo que hay realmente y el sistema
/// calcula la diferencia contra su stock.
class ConteoDialog extends StatefulWidget {
  final InventarioService servicio;
  final ExistenciaItem item;
  const ConteoDialog({super.key, required this.servicio, required this.item});

  @override
  State<ConteoDialog> createState() => _ConteoDialogState();
}

class _ConteoDialogState extends State<ConteoDialog> {
  final _real = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _real.dispose();
    _obs.dispose();
    super.dispose();
  }

  double? get _valor {
    final t = _real.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    final valor = _valor;
    if (valor == null) {
      setState(() => _error = 'Escribí la cantidad que contaste.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio
        .registrarConteo(widget.item, cantidadReal: valor, observaciones: _obs.text);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Conteo registrado.');
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
    final item = widget.item;
    final valor = _valor;
    final diferencia = valor == null ? null : valor - item.cantidadSistema;
    final colorDif = diferencia == null || diferencia == 0
        ? Colors.black54
        : (diferencia < 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A));

    return ModalFormulario(
      titulo: 'Conteo físico',
      icono: Icons.fact_check_outlined,
      textoBoton: 'Registrar conteo',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.detalle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(item.codigo, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Según el sistema'),
                Text('${fmtNum(item.cantidadSistema)} ${item.unidad}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _real,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cantidad real (${item.unidad})',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (diferencia != null) ...[
            const SizedBox(height: 8),
            Text(
              diferencia == 0
                  ? 'Coincide con el sistema.'
                  : 'Diferencia: ${diferencia > 0 ? '+' : ''}${fmtNum(diferencia)} ${item.unidad}'
                      ' (se guarda como ajuste).',
              style: TextStyle(color: colorDif, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _obs,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observaciones (opcional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
        ],
      ),
    );
  }
}
