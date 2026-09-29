import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../../entregas/models/entregas_modelos.dart' show AreaPedido;
import '../models/existencia_item.dart';
import '../services/inventario_service.dart';

/// Salida sin pedido formal ni firma (ej. termocontraíbles): a diferencia
/// de "Registrar movimiento", pide dos datos — cuántos rollos (o unidades)
/// salen y el peso REAL, porque no es una conversión fija. Lo que descuenta
/// el stock es el peso real.
class SalidaDirectaDialog extends StatefulWidget {
  final InventarioService servicio;
  const SalidaDirectaDialog({super.key, required this.servicio});

  @override
  State<SalidaDirectaDialog> createState() => _SalidaDirectaDialogState();
}

class _SalidaDirectaDialogState extends State<SalidaDirectaDialog> {
  ExistenciaItem? _item;
  String? _area;
  final _rollos = TextEditingController();
  final _peso = TextEditingController();
  final _motivo = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _rollos.dispose();
    _peso.dispose();
    _motivo.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.registrarSalidaDirecta(
      item: _item,
      areaDestino: _area,
      pesoReal: _num(_peso),
      cantidadRollos: _num(_rollos),
      motivo: _motivo.text,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Salida directa registrada.');
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
    final items = widget.servicio.existencias.where((e) => e.almacenId == 'general').toList()
      ..sort((a, b) => a.detalle.compareTo(b.detalle));

    return ModalFormulario(
      titulo: 'Salida directa',
      icono: Icons.local_shipping_outlined,
      textoBoton: 'Registrar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Sin pedido formal ni firma (ej. rollos de termocontraíble). '
              'El peso real es lo que descuenta el stock.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 12),
          DropdownButtonFormField<ExistenciaItem>(
            initialValue: _item,
            isExpanded: true,
            decoration: _deco('Ítem'),
            items: [
              for (final e in items)
                DropdownMenuItem(value: e, child: Text('${e.codigo} · ${e.detalle}')),
            ],
            onChanged: (v) => setState(() => _item = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _area,
            decoration: _deco('Área que lo recibe'),
            items: [
              for (final a in AreaPedido.todas)
                DropdownMenuItem(value: a, child: Text(AreaPedido.etiqueta(a))),
            ],
            onChanged: (v) => setState(() => _area = v),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _rollos,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Cantidad de rollos (opcional)', ayuda: 'Solo de referencia'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _peso,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Peso real${_item == null ? '' : ' (${_item!.unidad})'}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            maxLength: 300,
            maxLines: 2,
            decoration: _deco('Motivo (opcional)').copyWith(counterText: ''),
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
