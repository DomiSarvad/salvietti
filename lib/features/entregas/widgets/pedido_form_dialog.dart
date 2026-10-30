import 'package:flutter/material.dart';
import '../../../shared/busqueda_local.dart';
import '../../../models/usuario.dart';
import '../../../shared/alertas.dart';
import '../repositories/entregas_repository.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/entregas_modelos.dart';
import '../services/entregas_service.dart';

/// Alta de un pedido: el área elige qué necesita; Almacén puede además
/// entregarlo en el acto (por ejemplo, según el plan del día).
class PedidoFormDialog extends StatefulWidget {
  final EntregasService servicio;

  /// Ítems y cantidades ya cargados (por ejemplo, lo recién recibido en
  /// Recepciones), y si arranca con "Entregar ahora" prendido.
  final List<(int itemId, double cantidad)> iniciales;
  final bool entregarAhora;
  final String? motivo;
  const PedidoFormDialog({
    super.key,
    required this.servicio,
    this.iniciales = const [],
    this.entregarAhora = false,
    this.motivo,
  });

  /// Desde otro módulo (Recepciones): arma su propio service y abre el
  /// formulario ya cargado, listo para elegir el área y entregar.
  static Future<bool?> abrirCargado(
    BuildContext context, {
    required Usuario usuario,
    required List<(int, double)> lineas,
    String? motivo,
  }) {
    final svc = EntregasService(SupabaseEntregasRepository(), usuario);
    return showDialog<bool>(
      context: context,
      builder: (_) => PedidoFormDialog(
          servicio: svc, iniciales: lineas, entregarAhora: true, motivo: motivo),
    ).whenComplete(svc.dispose);
  }

  @override
  State<PedidoFormDialog> createState() => _PedidoFormDialogState();
}

class _LineaForm {
  ItemPedible? item;
  final controlador = TextEditingController();
  _LineaForm([this.item, double? cantidad]) {
    if (cantidad != null) controlador.text = _texto(cantidad);
  }
  static String _texto(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

class _PedidoFormDialogState extends State<PedidoFormDialog> {
  // Índice en memoria: el texto de cada ítem se normaliza una vez, no por letra.
  IndiceBusqueda<ItemPedible> _items = IndiceBusqueda(const [], _textoItem);

  static String _textoItem(ItemPedible i) => '${i.codigo} ${i.detalle}';
  bool _cargando = true;
  String? _area;
  final _motivo = TextEditingController();
  final _lineas = <_LineaForm>[_LineaForm()];
  late bool _entregarAhora = widget.entregarAhora;
  bool _guardando = false;
  String? _error;

  EntregasService get _svc => widget.servicio;

  @override
  void initState() {
    super.initState();
    _area = _svc.esAlmacen ? null : _svc.areaPropia;
    if (widget.motivo != null) _motivo.text = widget.motivo!;
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
        _items = IndiceBusqueda(items, _textoItem);
        _cargando = false;
        // Cargado de antemano: solo los ítems que existen en Almacén General.
        final porId = {for (final i in items) i.id: i};
        final cargadas = [
          for (final (id, cant) in widget.iniciales)
            if (porId[id] != null) _LineaForm(porId[id], cant)
        ];
        if (cargadas.isNotEmpty) {
          for (final l in _lineas) {
            l.controlador.dispose();
          }
          _lineas
            ..clear()
            ..addAll(cargadas);
        }
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
      avisoExito(context, _entregarAhora ? 'Entregado' : 'Pedido enviado',
          _entregarAhora ? 'El área tiene que confirmar lo que recibió.' : null);
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
              initialValue: linea.item == null
                  ? null
                  : TextEditingValue(text: '${linea.item!.codigo} · ${linea.item!.detalle}'),
              displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
              optionsBuilder: (t) =>
                  _items.buscar(t.text, limite: 50, donde: (i) => !elegidos.contains(i.id)),
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
