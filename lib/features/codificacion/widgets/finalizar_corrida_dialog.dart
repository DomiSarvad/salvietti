import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/codificacion_modelos.dart';
import '../services/codificacion_service.dart';

/// Cierra una corrida en curso: botellas codificadas, código o fecha
/// impresa, la merma (botellas y tapas mal tapadas, impurezas) y cuánto
/// solvente/tinta se usó.
class FinalizarCorridaDialog extends StatefulWidget {
  final CodificacionService servicio;
  final CorridaCodificacion corrida;
  const FinalizarCorridaDialog({super.key, required this.servicio, required this.corrida});

  @override
  State<FinalizarCorridaDialog> createState() => _FinalizarCorridaDialogState();
}

class _FinalizarCorridaDialogState extends State<FinalizarCorridaDialog> {
  final _botellasCodificadas = TextEditingController();
  final _codigoImpreso = TextEditingController();
  final _botellasMalTapadas = TextEditingController(text: '0');
  final _tapasMalTapadas = TextEditingController(text: '0');
  final _impurezas = TextEditingController(text: '0');
  final _motivoMerma = TextEditingController();
  final _solventeUsado = TextEditingController(text: '0');
  final _tintaUsada = TextEditingController(text: '0');
  final _obs = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _botellasCodificadas, _codigoImpreso, _botellasMalTapadas, _tapasMalTapadas, _impurezas,
      _motivoMerma, _solventeUsado, _tintaUsada, _obs,
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
    final botellas = _num(_botellasCodificadas);
    if (botellas == null) {
      setState(() => _error = 'Escribí las botellas codificadas.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.finalizarCorrida(
      widget.corrida,
      FinalizarCorridaCodificacion(
        botellasCodificadas: botellas,
        codigoImpreso: _codigoImpreso.text,
        botellasMalTapadas: _num(_botellasMalTapadas) ?? 0,
        tapasMalTapadas: _num(_tapasMalTapadas) ?? 0,
        impurezas: _num(_impurezas) ?? 0,
        motivoMerma: _motivoMerma.text,
        solventeUsado: _num(_solventeUsado) ?? 0,
        tintaUsada: _num(_tintaUsada) ?? 0,
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
    final hayMerma = (_num(_botellasMalTapadas) ?? 0) > 0 || (_num(_tapasMalTapadas) ?? 0) > 0
        || (_num(_impurezas) ?? 0) > 0;

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
            '${c.nLote == null ? '' : ' · Lote ${c.nLote}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          FilaCampos([
            _campoNum(_botellasCodificadas, 'Botellas codificadas'),
            TextField(
                controller: _codigoImpreso,
                decoration: _deco('Código o fecha impresa (opcional)')),
          ]),
          const SizedBox(height: 16),
          const Text('Merma', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilaCampos([
            _campoNum(_botellasMalTapadas, 'Botellas mal tapadas'),
            _campoNum(_tapasMalTapadas, 'Tapas mal tapadas'),
            _campoNum(_impurezas, 'Impurezas'),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoMerma,
            maxLength: 300,
            decoration: _deco('Motivo de la merma', ayuda: hayMerma ? 'Obligatorio' : null)
                .copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          const Text('Consumo', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilaCampos([
            _campoNum(_solventeUsado,
                'Solvente usado${c.itemSolventeDetalle == null ? '' : ' (${c.itemSolventeDetalle})'}'),
            _campoNum(_tintaUsada,
                'Tinta usada${c.itemTintaDetalle == null ? '' : ' (${c.itemTintaDetalle})'}'),
          ]),
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
