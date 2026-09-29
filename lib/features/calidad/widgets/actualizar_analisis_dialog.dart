import 'package:flutter/material.dart';
import '../../../widgets/formulario_widgets.dart';
import '../../../utils/notificaciones.dart';
import '../models/calidad_modelos.dart';
import '../services/calidad_service.dart';

/// Completa la acción tomada o las observaciones de un análisis ya
/// registrado, sin tocar la medición original (Brix, pH, resultado).
class ActualizarAnalisisDialog extends StatefulWidget {
  final CalidadService servicio;
  final AnalisisCalidad analisis;
  const ActualizarAnalisisDialog({super.key, required this.servicio, required this.analisis});

  @override
  State<ActualizarAnalisisDialog> createState() => _ActualizarAnalisisDialogState();
}

class _ActualizarAnalisisDialogState extends State<ActualizarAnalisisDialog> {
  late final _accion = TextEditingController(text: widget.analisis.accionTomada);
  late final _obs = TextEditingController(text: widget.analisis.observaciones);
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _accion.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.actualizarAnalisis(
      widget.analisis,
      accionTomada: _accion.text,
      observaciones: _obs.text,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Análisis actualizado.');
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
    return ModalFormulario(
      titulo: 'Actualizar análisis',
      icono: Icons.edit_note_outlined,
      textoBoton: 'Guardar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _accion,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Acción tomada', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observaciones', counterText: ''),
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
