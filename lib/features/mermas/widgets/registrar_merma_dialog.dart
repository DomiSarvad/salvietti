import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/mermas_modelos.dart';
import '../services/mermas_service.dart';

/// Registra una merma de Jarabes, Calidad o Vidrio: sabor, formato
/// (opcional), lo producido (opcional, para calcular el porcentaje), la
/// cantidad de cada causa del área y el motivo.
class RegistrarMermaDialog extends StatefulWidget {
  final MermasService servicio;
  const RegistrarMermaDialog({super.key, required this.servicio});

  @override
  State<RegistrarMermaDialog> createState() => _RegistrarMermaDialogState();
}

class _RegistrarMermaDialogState extends State<RegistrarMermaDialog> {
  AreaMerma? _area;
  Sabor? _sabor;
  Presentacion? _presentacion;
  final _producido = TextEditingController();
  final _motivo = TextEditingController();
  final Map<String, TextEditingController> _causas = {};
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final permitidas = widget.servicio.areasPermitidas;
    if (permitidas.length == 1) _elegirArea(permitidas.first);
  }

  @override
  void dispose() {
    _producido.dispose();
    _motivo.dispose();
    for (final c in _causas.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _elegirArea(AreaMerma? a) {
    setState(() {
      _area = a;
      _causas.clear();
      if (a != null) {
        for (final c in a.causas) {
          _causas[c.id] = TextEditingController();
        }
      }
    });
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
    final causas = <String, double>{
      for (final e in _causas.entries) e.key: _num(e.value) ?? 0,
    };
    final error = await widget.servicio.registrar(
      area: _area,
      saborId: _sabor?.id,
      causas: causas,
      presentacionId: _presentacion?.id,
      cantidadProducida: _num(_producido),
      motivo: _motivo.text,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Merma registrada.');
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
    final permitidas = svc.areasPermitidas;

    return ModalFormulario(
      titulo: 'Registrar merma',
      icono: Icons.report_problem_outlined,
      textoBoton: 'Guardar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<AreaMerma>(
            initialValue: _area,
            decoration: _deco('Área'),
            items: [for (final a in permitidas) DropdownMenuItem(value: a, child: Text(a.etiqueta))],
            onChanged: _elegirArea,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [for (final s in svc.sabores) DropdownMenuItem(value: s, child: Text(s.nombre))],
            onChanged: (v) => setState(() => _sabor = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Presentacion>(
            initialValue: _presentacion,
            decoration: _deco('Formato (opcional)'),
            items: [
              for (final p in svc.presentaciones) DropdownMenuItem(value: p, child: Text(p.nombre)),
            ],
            onChanged: (v) => setState(() => _presentacion = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _producido,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _deco('Cantidad producida (opcional)',
                ayuda: 'Si la indicás, se calcula el % de merma y la alerta del 3 %'),
          ),
          if (_area != null) ...[
            const SizedBox(height: 16),
            const Text('Causas', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final c in _area!.causas)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _causas[c.id],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _deco(c.etiqueta),
                ),
              ),
          ],
          TextField(
            controller: _motivo,
            maxLength: 300,
            maxLines: 2,
            decoration: _deco('Motivo (opcional)').copyWith(counterText: ''),
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
