import 'package:flutter/material.dart';
import '../../../shared/busqueda_local.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/jarabes_modelos.dart';
import '../services/jarabes_service.dart';

class _LineaForm {
  ItemJarabes? item;
  final controlador = TextEditingController();
}

/// Propone una receta para un sabor: sabor + lista de insumos y cantidad
/// por preparado. Queda pendiente hasta que alguien con permiso la aprueba.
class ProponerRecetaDialog extends StatefulWidget {
  final JarabesService servicio;
  const ProponerRecetaDialog({super.key, required this.servicio});

  @override
  State<ProponerRecetaDialog> createState() => _ProponerRecetaDialogState();
}

class _ProponerRecetaDialogState extends State<ProponerRecetaDialog> {
  Sabor? _sabor;
  final _lineas = <_LineaForm>[_LineaForm()];
  // Índice en memoria: el texto de cada ítem se normaliza una vez, no por letra.
  IndiceBusqueda<ItemJarabes> _catalogo = IndiceBusqueda(const [], _textoItem);

  static String _textoItem(ItemJarabes i) => '${i.codigo} ${i.detalle}';
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.servicio.catalogoItems().then((r) {
      if (mounted) setState(() => _catalogo = IndiceBusqueda(r, _textoItem));
    });
  }

  @override
  void dispose() {
    for (final l in _lineas) {
      l.controlador.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Map<int, double> get _items => {
        for (final l in _lineas)
          if (l.item != null && _num(l.controlador) != null && _num(l.controlador)! > 0)
            l.item!.id: _num(l.controlador)!,
      };

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.proponerReceta(_sabor?.id, _items);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Receta enviada para aprobación.');
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
      titulo: 'Proponer receta',
      icono: Icons.receipt_long_outlined,
      textoBoton: 'Enviar para aprobación',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [
              for (final s in widget.servicio.sabores)
                DropdownMenuItem(value: s, child: Text(s.nombre)),
            ],
            onChanged: (s) => setState(() => _sabor = s),
          ),
          const SizedBox(height: 12),
          const Text('Insumos por preparado', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (int i = 0; i < _lineas.length; i++) _filaItem(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lineas.add(_LineaForm())),
              icon: const Icon(Icons.add),
              label: const Text('Agregar insumo'),
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
            child: Autocomplete<ItemJarabes>(
              displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
              optionsBuilder: (t) =>
                  _catalogo.buscar(t.text, limite: 50, donde: (i) => !elegidos.contains(i.id)),
              onSelected: (i) => setState(() => linea.item = i),
              fieldViewBuilder: (context, c, foco, _) => TextField(
                controller: c,
                focusNode: foco,
                onChanged: (t) {
                  if (linea.item != null && t != '${linea.item!.codigo} · ${linea.item!.detalle}') {
                    linea.item = null;
                  }
                },
                decoration: _deco('Insumo'),
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
