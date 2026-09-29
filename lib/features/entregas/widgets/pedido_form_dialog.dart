import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../utils/texto.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/entregas_modelos.dart';
import '../services/entregas_service.dart';

/// Alta de un pedido: el área elige qué necesita; Almacén puede además
/// entregarlo en el acto (por ejemplo, según el plan del día).
class PedidoFormDialog extends StatefulWidget {
  final EntregasService servicio;
  const PedidoFormDialog({super.key, required this.servicio});

  @override
  State<PedidoFormDialog> createState() => _PedidoFormDialogState();
}

class _LineaForm {
  ItemPedible? item;
  final controlador = TextEditingController();
}

class _PedidoFormDialogState extends State<PedidoFormDialog> {
  List<ItemPedible> _items = [];
  bool _cargando = true;
  String? _area;
  final _motivo = TextEditingController();
  final _lineas = <_LineaForm>[_LineaForm()];
  bool _entregarAhora = false;
  bool _guardando = false;
  String? _error;

  EntregasService get _svc => widget.servicio;

  @override
  void initState() {
    super.initState();
    _area = _svc.esAlmacen ? null : _svc.areaPropia;
    _cargar();
  }

  @override
  void dispose() {
    _motivo.dispose();
    for (final l in _lineas) {
      l.controlador.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final items = await _svc.itemsPedibles();
      if (!mounted) return;
      setState(() {
        _items = items;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los ítems del Almacén General.';
      });
    }
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  List<LineaNueva> get _lineasValidas => [
        for (final l in _lineas)
          if (l.item != null && _num(l.controlador) != null && _num(l.controlador)! > 0)
            LineaNueva(itemId: l.item!.id, cantidad: _num(l.controlador)!),
      ];

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await _svc.crearPedido(
      area: _area,
      motivo: _motivo.text,
      lineas: _lineasValidas,
      entregarAhora: _entregarAhora,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, _entregarAhora ? 'Pedido registrado y entregado.' : 'Pedido enviado.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    return ModalFormulario(
      titulo: 'Nuevo pedido',
      icono: Icons.assignment_outlined,
      textoBoton: _entregarAhora ? 'Registrar y entregar' : 'Enviar pedido',
      guardando: _guardando,
      onGuardar: _cargando ? null : _guardar,
      ancho: 560,
      child: _cargando
          ? const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_svc.esAlmacen) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _area,
                    decoration: _deco('Área que recibe'),
                    items: [
                      for (final a in AreaPedido.todas)
                        DropdownMenuItem(value: a, child: Text(AreaPedido.etiqueta(a))),
                    ],
                    onChanged: (v) => setState(() => _area = v),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _entregarAhora,
                    onChanged: (v) => setState(() => _entregarAhora = v),
                    title: const Text('Entregar ahora'),
                    subtitle: const Text(
                        'Por ejemplo, según el plan del día. Si no, queda pendiente para entregar después.'),
                  ),
                  const SizedBox(height: 4),
                ],
                TextField(
                  controller: _motivo,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: _deco('Motivo (opcional)').copyWith(counterText: ''),
                ),
                const SizedBox(height: 12),
                const Text('Ítems', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (int i = 0; i < _lineas.length; i++) _filaItem(i),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _lineas.add(_LineaForm())),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar ítem'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
                ],
              ],
            ),
    );
  }

  Widget _filaItem(int i) {
    final linea = _lineas[i];
    final elegidos = _lineas.where((l) => l != linea).map((l) => l.item?.id).toSet();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Autocomplete<ItemPedible>(
              displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
              optionsBuilder: (t) {
                final q = sinTildes(t.text.trim());
                return _items.where((i) =>
                    !elegidos.contains(i.id) &&
                    (q.isEmpty || sinTildes(i.detalle).contains(q) || sinTildes(i.codigo).contains(q)));
              },
              onSelected: (i) => setState(() => linea.item = i),
              fieldViewBuilder: (context, c, foco, _) => TextField(
                controller: c,
                focusNode: foco,
                onChanged: (t) {
                  if (linea.item != null && t != '${linea.item!.codigo} · ${linea.item!.detalle}') {
                    linea.item = null;
                  }
                },
                decoration: _deco('Ítem'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: linea.controlador,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: _deco(linea.item == null ? 'Cantidad' : linea.item!.unidad),
            ),
          ),
          IconButton(
            tooltip: 'Quitar',
            onPressed: _lineas.length == 1
                ? null
                : () => setState(() {
                      _lineas.removeAt(i).controlador.dispose();
                    }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
