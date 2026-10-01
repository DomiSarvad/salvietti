import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/soplado_modelos.dart';
import '../services/soplado_service.dart';

/// Cierra una corrida en curso: botellas sopladas y etiquetadas, preformas
/// usadas (se descuentan del almacén de Soplado), las tres mermas del
/// reporte real (preforma, soplado, etiquetado) y la parada de máquina, si
/// la hubo.
class FinalizarCorridaDialog extends StatefulWidget {
  final SopladoService servicio;
  final CorridaSoplado corrida;
  const FinalizarCorridaDialog({super.key, required this.servicio, required this.corrida});

  @override
  State<FinalizarCorridaDialog> createState() => _FinalizarCorridaDialogState();
}

class _FinalizarCorridaDialogState extends State<FinalizarCorridaDialog> {
  final _botellasSopladas = TextEditingController();
  final _preformas = TextEditingController();
  final _botellasEtiquetadas = TextEditingController();
  final _mermaPreforma = TextEditingController(text: '0');
  final _mermaSoplado = TextEditingController(text: '0');
  final _mermaEtiquetado = TextEditingController(text: '0');
  final _tiempoParada = TextEditingController();
  final _motivoParada = TextEditingController();
  final _motivoMerma = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _botellasSopladas, _preformas, _botellasEtiquetadas, _mermaPreforma, _mermaSoplado,
      _mermaEtiquetado, _tiempoParada, _motivoParada, _motivoMerma, _obs,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  int _entero(TextEditingController c) => (_num(c) ?? 0).round();

  Future<void> _guardar() async {
    final botellas = _num(_botellasSopladas);
    final preformas = _num(_preformas);
    if (botellas == null) {
      setState(() => _error = 'Escribí las botellas sopladas.');
      return;
    }
    if (preformas == null) {
      setState(() => _error = 'Escribí las preformas usadas.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.finalizarCorrida(
      widget.corrida,
      FinalizarCorrida(
        botellasSopladas: botellas,
        preformasUsadas: preformas,
        mermaPreforma: _entero(_mermaPreforma),
        mermaSoplado: _entero(_mermaSoplado),
        botellasEtiquetadas: _num(_botellasEtiquetadas),
        mermaEtiquetado: _entero(_mermaEtiquetado),
        tiempoParadaMinutos: _num(_tiempoParada)?.round(),
        motivoParada: _motivoParada.text,
        motivoMerma: _motivoMerma.text,
        observaciones: _obs.text,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Corrida finalizada.');
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

  Widget _campoNum(TextEditingController c, String label, {String? ayuda}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: _deco(label, ayuda: ayuda),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.corrida;
    final hayMerma =
        (_num(_mermaPreforma) ?? 0) > 0 || (_num(_mermaSoplado) ?? 0) > 0 || (_num(_mermaEtiquetado) ?? 0) > 0;
    final hayParada = (_num(_tiempoParada) ?? 0) > 0;

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
            '${c.lotePreforma == null ? '' : ' · Lote preforma: ${c.lotePreforma}'}'
            '${c.proveedorNombre == null ? '' : ' · ${c.proveedorNombre}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          FilaCampos([
            _campoNum(_preformas, 'Preformas usadas'),
            _campoNum(_mermaPreforma, 'Merma de preforma'),
          ]),
          const SizedBox(height: 12),
          FilaCampos([
            _campoNum(_botellasSopladas, 'Botellas sopladas'),
            _campoNum(_mermaSoplado, 'Merma de soplado'),
          ]),
          const SizedBox(height: 12),
          FilaCampos([
            _campoNum(_botellasEtiquetadas, 'Botellas etiquetadas (opcional)'),
            _campoNum(_mermaEtiquetado, 'Merma de etiquetado'),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoMerma,
            maxLength: 300,
            decoration: _deco('Motivo de la merma', ayuda: hayMerma ? 'Obligatorio' : null)
                .copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          const Text('Parada de máquina (opcional)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FilaCampos([
            _campoNum(_tiempoParada, 'Tiempo de parada (min)'),
            TextField(
              controller: _motivoParada,
              maxLength: 300,
              decoration: _deco('Motivo', ayuda: hayParada ? 'Obligatorio' : null)
                  .copyWith(counterText: ''),
            ),
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
