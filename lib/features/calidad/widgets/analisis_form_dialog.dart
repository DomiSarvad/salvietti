import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/calidad_modelos.dart';
import '../services/calidad_service.dart';

/// Registra el análisis de un preparado de Jarabes ya finalizado: Brix
/// diluido, pH, aspecto y el resultado (con acción obligatoria si no
/// cumple).
class AnalisisFormDialog extends StatefulWidget {
  final CalidadService servicio;
  final PreparadoPendiente preparado;
  const AnalisisFormDialog({super.key, required this.servicio, required this.preparado});

  @override
  State<AnalisisFormDialog> createState() => _AnalisisFormDialogState();
}

class _AnalisisFormDialogState extends State<AnalisisFormDialog> {
  final _brix = TextEditingController();
  final _ph = TextEditingController();
  final _aspecto = TextEditingController();
  final _accion = TextEditingController();
  final _obs = TextEditingController();
  String _resultado = 'conforme';
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_brix, _ph, _aspecto, _accion, _obs]) {
      c.dispose();
    }
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
    final error = await widget.servicio.registrarAnalisis(NuevoAnalisis(
      preparadoId: widget.preparado.preparadoId,
      brixDiluido: _num(_brix),
      ph: _num(_ph),
      resultado: _resultado,
      aspecto: _aspecto.text,
      accionTomada: _accion.text,
      observaciones: _obs.text,
    ));
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Análisis registrado.');
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
    final p = widget.preparado;
    final rango = (p.brixMin != null || p.brixMax != null)
        ? 'Objetivo del sabor: ${p.brixMin ?? '—'} a ${p.brixMax ?? '—'}'
        : null;
    final noConforme = _resultado == 'no_conforme';

    return ModalFormulario(
      titulo: 'Registrar análisis',
      icono: Icons.science_outlined,
      textoBoton: 'Guardar análisis',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${p.sabor} · Lote ${p.nLote}${p.tanque == null ? '' : ' · Tanque ${p.tanque}'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'Brix de Jarabes: ${p.brix == null ? '—' : fmtNum(p.brix, decimales: 1)}'
            '${p.brixFueraDeRango ? ' (fuera de rango)' : ''}'
            '${rango == null ? '' : ' · $rango'}',
            style: TextStyle(
                fontSize: 12,
                color: p.brixFueraDeRango ? const Color(0xFFDC2626) : Colors.black54),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _brix,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('Brix diluido'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ph,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco('pH'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aspecto,
            maxLength: 200,
            decoration: _deco('Aspecto / color (opcional)').copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'conforme', label: Text('Conforme')),
              ButtonSegment(value: 'no_conforme', label: Text('No conforme')),
            ],
            selected: {_resultado},
            onSelectionChanged: (s) => setState(() => _resultado = s.first),
          ),
          if (noConforme) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _accion,
              maxLength: 300,
              maxLines: 2,
              decoration: _deco('Acción tomada', ayuda: 'Obligatoria: notifica a Jarabes y Producción')
                  .copyWith(counterText: ''),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            maxLength: 300,
            maxLines: 2,
            decoration: _deco('Observaciones (opcional)').copyWith(counterText: ''),
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
