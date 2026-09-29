import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/solicitud.dart';
import '../services/solicitudes_service.dart';

/// Alta de una solicitud a Gerencia: tipo, asunto, detalle y, si aplica,
/// el ítem que falta y la cantidad sugerida.
class SolicitudFormDialog extends StatefulWidget {
  final SolicitudesService servicio;
  const SolicitudFormDialog({super.key, required this.servicio});

  @override
  State<SolicitudFormDialog> createState() => _SolicitudFormDialogState();
}

class _SolicitudFormDialogState extends State<SolicitudFormDialog> {
  String _tipo = TipoSolicitud.suministro;
  final _asunto = TextEditingController();
  final _detalle = TextEditingController();
  final _cantidad = TextEditingController();
  ItemReferencia? _item;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _asunto.dispose();
    _detalle.dispose();
    _cantidad.dispose();
    super.dispose();
  }

  double? get _cantidadValor {
    final t = _cantidad.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.crear(SolicitudNueva(
      tipo: _tipo,
      asunto: _asunto.text,
      detalle: _detalle.text,
      itemId: _tipo == TipoSolicitud.suministro ? _item?.id : null,
      cantidadSugerida: _tipo == TipoSolicitud.suministro ? _cantidadValor : null,
    ));
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Solicitud enviada a Gerencia.');
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
    return ModalFormulario(
      titulo: 'Nueva solicitud a Gerencia',
      icono: Icons.mark_email_read_outlined,
      textoBoton: 'Enviar solicitud',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: _deco('Tipo de solicitud'),
            items: [
              for (final t in TipoSolicitud.todos)
                DropdownMenuItem(value: t, child: Text(TipoSolicitud.etiqueta(t))),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? _tipo),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _asunto,
            maxLength: 120,
            decoration: _deco('Asunto').copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          if (_tipo == TipoSolicitud.suministro) ...[
            Autocomplete<ItemReferencia>(
              displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
              optionsBuilder: (t) => widget.servicio.buscarItems(t.text),
              onSelected: (i) => setState(() => _item = i),
              fieldViewBuilder: (context, c, foco, _) => TextField(
                controller: c,
                focusNode: foco,
                onChanged: (t) {
                  if (_item != null && t != '${_item!.codigo} · ${_item!.detalle}') {
                    _item = null;
                  }
                },
                decoration: _deco('Ítem que falta (opcional)',
                    ayuda: 'Escribí para buscar en el catálogo'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cantidad,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco('Cantidad sugerida (opcional)',
                  ayuda: _item == null ? null : 'en ${_item!.unidad}'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _detalle,
            maxLength: 500,
            maxLines: 4,
            decoration: _deco('Detalle').copyWith(counterText: ''),
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
