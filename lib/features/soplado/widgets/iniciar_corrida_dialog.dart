import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/soplado_modelos.dart';
import '../services/soplado_service.dart';

/// Inicia una corrida de soplado: sabor, presentación (solo las que existen
/// para ese sabor) y, opcional, la preforma que se va a usar. La hora de
/// inicio la pone el servidor.
class IniciarCorridaDialog extends StatefulWidget {
  final SopladoService servicio;
  const IniciarCorridaDialog({super.key, required this.servicio});

  @override
  State<IniciarCorridaDialog> createState() => _IniciarCorridaDialogState();
}

class _IniciarCorridaDialogState extends State<IniciarCorridaDialog> {
  Sabor? _sabor;
  Presentacion? _presentacion;
  ItemPreforma? _preforma;
  Proveedor? _proveedor;
  final _lote = TextEditingController();
  Set<int>? _presentacionesValidas;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _lote.dispose();
    super.dispose();
  }

  Future<void> _elegirSabor(Sabor? s) async {
    setState(() {
      _sabor = s;
      _presentacion = null;
      _presentacionesValidas = null;
    });
    if (s == null) return;
    final validas = await widget.servicio.presentacionesDe(s.id);
    if (mounted && _sabor?.id == s.id) setState(() => _presentacionesValidas = validas);
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.iniciarCorrida(
      saborId: _sabor?.id,
      presentacionId: _presentacion?.id,
      itemPreformaId: _preforma?.id,
      proveedorId: _proveedor?.id,
      lotePreforma: _lote.text,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Corrida iniciada.');
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
    final presentacionesDisponibles = _presentacionesValidas == null
        ? const <Presentacion>[]
        : svc.presentaciones.where((p) => _presentacionesValidas!.contains(p.id)).toList();

    return ModalFormulario(
      titulo: 'Iniciar corrida de soplado',
      icono: Icons.play_circle_outline,
      textoBoton: 'Iniciar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [
              for (final s in svc.sabores) DropdownMenuItem(value: s, child: Text(s.nombre)),
            ],
            onChanged: _elegirSabor,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Presentacion>(
            initialValue: _presentacion,
            decoration: _deco('Presentación',
                ayuda: _sabor == null
                    ? 'Elegí primero el sabor'
                    : (presentacionesDisponibles.isEmpty
                        ? 'Ese sabor no tiene presentaciones de PET cargadas'
                        : null)),
            items: [
              for (final p in presentacionesDisponibles)
                DropdownMenuItem(value: p, child: Text(p.nombre)),
            ],
            onChanged: _sabor == null ? null : (v) => setState(() => _presentacion = v),
          ),
          const SizedBox(height: 12),
          Autocomplete<ItemPreforma>(
            displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
            optionsBuilder: (t) => svc.buscarPreformas(t.text),
            onSelected: (i) => setState(() => _preforma = i),
            fieldViewBuilder: (context, c, foco, _) => TextField(
              controller: c,
              focusNode: foco,
              onChanged: (t) {
                if (_preforma != null && t != '${_preforma!.codigo} · ${_preforma!.detalle}') {
                  _preforma = null;
                }
              },
              decoration: _deco('Preforma (opcional)',
                  ayuda: 'Si la indicás, al finalizar se descuenta sola del almacén de Soplado'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Autocomplete<Proveedor>(
                  displayStringForOption: (p) => p.nombre,
                  optionsBuilder: (t) => svc.buscarProveedores(t.text),
                  onSelected: (p) => setState(() => _proveedor = p),
                  fieldViewBuilder: (context, c, foco, _) => TextField(
                    controller: c,
                    focusNode: foco,
                    onChanged: (t) {
                      if (_proveedor != null && t != _proveedor!.nombre) _proveedor = null;
                    },
                    decoration: _deco('Proveedor de la preforma (opcional)'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lote,
                  decoration: _deco('Lote (opcional)'),
                ),
              ),
            ],
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
