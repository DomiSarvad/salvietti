import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/item_inventario.dart';
import '../models/unidad_medida.dart';
import '../services/inventario_service.dart';

/// Alta y edición de un ítem del catálogo. Solo recoge datos: las
/// validaciones las hace el service.
class ItemFormDialog extends StatefulWidget {
  final InventarioService servicio;
  final ItemInventario? item; // null = alta
  final int? categoriaInicial;
  const ItemFormDialog({
    super.key,
    required this.servicio,
    this.item,
    this.categoriaInicial,
  });

  @override
  State<ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<ItemFormDialog> {
  late final TextEditingController _detalle;
  late final TextEditingController _unidadCompra;
  late final TextEditingController _factor;
  late final TextEditingController _porCaja;
  late final TextEditingController _minimo;
  late final TextEditingController _consumo;
  late final TextEditingController _color;
  late final TextEditingController _formato;
  late final TextEditingController _peso;
  late final TextEditingController _ancho;
  late final TextEditingController _micronaje;

  int? _categoriaId;
  String _unidad = 'UNI';
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.item != null;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    String t(Object? v) => v == null ? '' : v.toString().replaceFirst(RegExp(r'\.0$'), '');
    _detalle = TextEditingController(text: i?.detalle ?? '');
    _unidadCompra = TextEditingController(text: i?.unidadCompra ?? '');
    _factor = TextEditingController(text: t(i?.factorCompra));
    _porCaja = TextEditingController(text: t(i?.unidadesPorCaja));
    _minimo = TextEditingController(text: t(i?.stockMinimo));
    _consumo = TextEditingController(text: t(i?.consumoDiarioManual));
    _color = TextEditingController(text: t(i?.atributos['color']));
    _formato = TextEditingController(text: t(i?.atributos['formato']));
    _peso = TextEditingController(text: t(i?.atributos['peso_g']));
    _ancho = TextEditingController(text: t(i?.atributos['ancho_mm']));
    _micronaje = TextEditingController(text: t(i?.atributos['micronaje']));
    _categoriaId = i?.categoriaId ?? _hojaInicial(widget.categoriaInicial);
    if (i != null) _unidad = i.unidad;
  }

  /// Solo una categoría propia y sin subcategorías puede recibir un ítem
  /// nuevo (una foránea es de solo lectura: llegó como stock de otra área).
  int? _hojaInicial(int? id) {
    if (id == null) return null;
    final esPropia = widget.servicio.categoriasPropias.any((c) => c.id == id);
    if (!esPropia) return null;
    return widget.servicio.hijosDe(id).isEmpty ? id : null;
  }

  @override
  void dispose() {
    for (final c in [
      _detalle, _unidadCompra, _factor, _porCaja, _minimo, _consumo,
      _color, _formato, _peso, _ancho, _micronaje,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  String? _texto(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _guardar() async {
    // Un número mal escrito no se ignora en silencio.
    for (final par in {
      'factor de compra': _factor,
      'unidades por caja': _porCaja,
      'stock mínimo': _minimo,
      'consumo diario': _consumo,
      'peso': _peso,
      'ancho': _ancho,
      'micronaje': _micronaje,
    }.entries) {
      if (par.value.text.trim().isNotEmpty && _num(par.value) == null) {
        setState(() => _error = 'El campo ${par.key} debe ser un número.');
        return;
      }
    }
    if (_categoriaId == null) {
      setState(() => _error = 'Elegí una categoría.');
      return;
    }

    final atributos = <String, dynamic>{
      if (_texto(_color) != null) 'color': _texto(_color),
      if (_texto(_formato) != null) 'formato': _texto(_formato),
      if (_num(_peso) != null) 'peso_g': _num(_peso),
      if (_num(_ancho) != null) 'ancho_mm': _num(_ancho),
      if (_num(_micronaje) != null) 'micronaje': _num(_micronaje),
    };

    final item = ItemInventario(
      id: widget.item?.id,
      categoriaId: _categoriaId!,
      detalle: _detalle.text.trim(),
      unidad: _unidad,
      unidadCompra: _texto(_unidadCompra),
      factorCompra: _num(_factor),
      unidadesPorCaja: _num(_porCaja)?.round(),
      stockMinimo: _num(_minimo),
      consumoDiarioManual: _num(_consumo),
      atributos: atributos,
    );

    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.guardarItem(item);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, _esEdicion ? 'Ítem actualizado.' : 'Ítem creado.');
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
        helperMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      );

  Widget _campo(TextEditingController c, String label,
      {String? ayuda, bool numerico = false, int? max}) {
    return TextField(
      controller: c,
      maxLength: max,
      keyboardType: numerico
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: _deco(label, ayuda: ayuda).copyWith(counterText: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.servicio;
    final hojas = svc.categoriasPropias
        .where((c) => svc.hijosDe(c.id).isEmpty)
        .map((c) => MapEntry(c.id, svc.textoRuta(c.id)))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    const sep = SizedBox(height: 12);

    return ModalFormulario(
      titulo: _esEdicion ? 'Editar ítem' : 'Nuevo ítem',
      icono: Icons.inventory_2_outlined,
      textoBoton: _esEdicion ? 'Guardar cambios' : 'Crear ítem',
      guardando: _guardando,
      onGuardar: _guardar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: hojas.any((h) => h.key == _categoriaId) ? _categoriaId : null,
            isExpanded: true,
            decoration: _deco('Categoría'),
            items: [
              for (final h in hojas)
                DropdownMenuItem(
                    value: h.key, child: Text(h.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _categoriaId = v),
          ),
          sep,
          _campo(_detalle, 'Detalle', max: 120),
          if (_esEdicion && widget.item?.codigo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('Código: ${widget.item!.codigo}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          sep,
          DropdownButtonFormField<String>(
            initialValue: _unidad,
            decoration: _deco('Unidad de medida'),
            items: [
              for (final u in UnidadMedida.todas)
                DropdownMenuItem(value: u, child: Text(UnidadMedida.etiqueta(u))),
            ],
            onChanged: (v) => setState(() => _unidad = v ?? _unidad),
          ),
          sep,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _campo(_unidadCompra, 'Se compra en',
                      ayuda: 'quintal, bidón, bolsa…', max: 30)),
              const SizedBox(width: 10),
              Expanded(
                  child: _campo(_factor, '$_unidad por envase',
                      ayuda: 'ej. 46', numerico: true)),
            ],
          ),
          sep,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _campo(_porCaja, 'Unidades por caja', numerico: true)),
              const SizedBox(width: 10),
              Expanded(
                  child: _campo(_minimo, 'Stock mínimo',
                      ayuda: 'Marca "Pedido"', numerico: true)),
            ],
          ),
          sep,
          _campo(_consumo, 'Consumo diario manual',
              ayuda: 'Solo si todavía no hay salidas registradas', numerico: true),
          const SizedBox(height: 16),
          const Text('Características (opcional)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _campo(_color, 'Color', max: 40)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_formato, 'Formato', ayuda: 'Short, Long…', max: 40)),
            ],
          ),
          sep,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _campo(_peso, 'Peso (g)', numerico: true)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_ancho, 'Ancho (mm)', numerico: true)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_micronaje, 'Micronaje', numerico: true)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }
}
