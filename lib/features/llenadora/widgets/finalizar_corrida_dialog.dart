import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/llenadora_modelos.dart';
import '../services/llenadora_service.dart';

/// Cierra una corrida en curso: botellas llenadas, y la merma (botellas
/// desechadas, tapas usadas y desechadas, rebalse).
class FinalizarCorridaDialog extends StatefulWidget {
  final LlenadoraService servicio;
  final CorridaLlenadora corrida;
  const FinalizarCorridaDialog({super.key, required this.servicio, required this.corrida});

  @override
  State<FinalizarCorridaDialog> createState() => _FinalizarCorridaDialogState();
}

class _FinalizarCorridaDialogState extends State<FinalizarCorridaDialog> {
  final _botellasLlenadas = TextEditingController();
  final _botellasDesechadas = TextEditingController(text: '0');
  final _tapasUsadas = TextEditingController(text: '0');
  final _tapasDesechadas = TextEditingController(text: '0');
  final _rebalse = TextEditingController(text: '0');
  final _motivoMerma = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _botellasLlenadas, _botellasDesechadas, _tapasUsadas, _tapasDesechadas, _rebalse,
      _motivoMerma, _obs,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    final botellas = _num(_botellasLlenadas);
    if (botellas == null) {
      setState(() => _error = 'Escribí las botellas llenadas.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.finalizarCorrida(
      widget.corrida,
      FinalizarCorridaLlenadora(
        botellasLlenadas: botellas,
        botellasDesechadas: _num(_botellasDesechadas) ?? 0,
        tapasUsadas: _num(_tapasUsadas) ?? 0,
        tapasDesechadas: _num(_tapasDesechadas) ?? 0,
        rebalse: _num(_rebalse) ?? 0,
        motivoMerma: _motivoMerma.text,
        observaciones: _obs.text,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      avisoExito(context, 'Corrida finalizada');
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

  Widget _campoNum(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: _deco(label),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.corrida;
    final hayMerma = (_num(_botellasDesechadas) ?? 0) > 0 || (_num(_tapasDesechadas) ?? 0) > 0
        || (_num(_rebalse) ?? 0) > 0;

    return ModalFormulario(
      titulo: 'Finalizar corrida',
      icono: Icons.stop_circle_outlined,
      textoBoton: 'Finalizar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${c.sabor ?? ''} · ${c.presentacion ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            'Inicio: ${fmtFechaHora(c.horaInicio)}'
            '${c.referenciaLote.isEmpty ? '' : ' · ${c.referenciaLote}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          _campoNum(_botellasLlenadas, 'Botellas llenadas'),
          const SizedBox(height: 16),
          const Text('Merma', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilaCampos([
            _campoNum(_botellasDesechadas, 'Botellas desechadas'),
            _campoNum(_rebalse, 'Rebalse'),
          ]),
          const SizedBox(height: 12),
          FilaCampos([
            _campoNum(_tapasUsadas, 'Tapas usadas'),
            _campoNum(_tapasDesechadas, 'Tapas desechadas'),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoMerma,
            maxLength: 300,
            decoration: _deco('Motivo de la merma', ayuda: hayMerma ? 'Obligatorio' : null)
                .copyWith(counterText: ''),
          ),
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
