import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/notificaciones.dart';
import '../models/compras_modelos.dart';
import '../services/compras_service.dart';

class _Linea {
  ItemCompra? item;
  final cantidad = TextEditingController();
  final nota = TextEditingController();
  void dispose() {
    cantidad.dispose();
    nota.dispose();
  }
}

/// Almacén arma un pedido de compra con varias líneas (ítem + cantidad +
/// nota opcional) y un motivo general. Lo aprueba o rechaza el Gerente.
class NuevoPedidoCompraDialog extends StatefulWidget {
  final ComprasService servicio;
  const NuevoPedidoCompraDialog({super.key, required this.servicio});

  @override
  State<NuevoPedidoCompraDialog> createState() => _NuevoPedidoCompraDialogState();
}

class _NuevoPedidoCompraDialogState extends State<NuevoPedidoCompraDialog> {
  final _motivo = TextEditingController();
  final _lineas = <_Linea>[_Linea()];
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.servicio.precargarItems(); // la primera letra ya busca en memoria
  }

  @override
  void dispose() {
    _motivo.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  double? _num(String t) {
    final s = t.trim().replaceAll(',', '.');
    return s.isEmpty ? null : double.tryParse(s);
  }

  Future<void> _guardar() async {
    final lineas = <LineaNueva>[];
    for (final l in _lineas) {
      if (l.item == null && l.cantidad.text.trim().isEmpty) continue; // fila vacía
      if (l.item == null) {
        setState(() => _error = 'Elegí el ítem en todas las filas (o borrá las que sobran).');
        return;
      }
      final c = _num(l.cantidad.text);
      if (c == null) {
        setState(() => _error = 'Escribí la cantidad de "${l.item!.detalle}".');
        return;
      }
      lineas.add(LineaNueva(item: l.item!, cantidad: c, nota: l.nota.text));
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.crear(_motivo.text, lineas);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Pedido de compra enviado al Gerente.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  Widget _fila(int i) {
    final l = _lineas[i];
    final elegidos = {for (final o in _lineas) if (o != l && o.item != null) o.item!.id};
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Autocomplete<ItemCompra>(
                    displayStringForOption: (it) => '${it.codigo} · ${it.detalle}',
                    optionsBuilder: (t) async => (await widget.servicio.buscarItems(t.text))
                        .where((it) => !elegidos.contains(it.id)),
                    onSelected: (it) => setState(() => l.item = it),
                    fieldViewBuilder: (context, c, foco, _) => TextField(
                      controller: c,
                      focusNode: foco,
                      onChanged: (_) {
                        if (l.item != null) setState(() => l.item = null);
                      },
                      decoration: const InputDecoration(
                          labelText: 'Ítem', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar fila',
                  onPressed: _lineas.length == 1
                      ? null
                      : () => setState(() => _lineas.removeAt(i).dispose()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: l.cantidad,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Cantidad',
                          suffixText: l.item?.unidad,
                          isDense: true,
                          border: const OutlineInputBorder()),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
                    child: TextField(
                      controller: l.nota,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          labelText: 'Nota (opcional)',
                          counterText: '',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Nuevo pedido de compra'),
      content: SizedBox(
        width: ancho < 600 ? ancho : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Lo aprueba o rechaza el Gerente. No mueve stock: el stock entra '
                  'cuando llega la mercadería (Recepciones).',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 12),
              for (var i = 0; i < _lineas.length; i++) _fila(i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _lineas.length >= ComprasService.maxLineas
                      ? null
                      : () => setState(() => _lineas.add(_Linea())),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar ítem'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _motivo,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                    hintText: 'Ej.: stock bajo de tapas para la semana que viene',
                    border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Enviando…' : 'Enviar al Gerente'),
        ),
      ],
    );
  }
}
