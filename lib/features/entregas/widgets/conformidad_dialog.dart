import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/entregas_modelos.dart';
import '../services/entregas_service.dart';

/// El área revisa lo entregado ítem por ítem: tilda lo que llegó bien y
/// escribe una observación en lo que no, antes de cerrar con "conforme".
class ConformidadDialog extends StatefulWidget {
  final EntregasService servicio;
  final Pedido pedido;
  const ConformidadDialog({super.key, required this.servicio, required this.pedido});

  @override
  State<ConformidadDialog> createState() => _ConformidadDialogState();
}

class _EstadoLinea {
  bool ok = true;
  late final TextEditingController cantidad;
  final observacion = TextEditingController();
  _EstadoLinea(double entregada) : cantidad = TextEditingController(text: _fmt(entregada));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _ConformidadDialogState extends State<ConformidadDialog> {
  late final Map<int, _EstadoLinea> _estados;
  final _nota = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _estados = {
      for (final l in widget.pedido.lineas) l.id: _EstadoLinea(l.cantidadEntregada ?? 0)
    };
  }

  @override
  void dispose() {
    _nota.dispose();
    for (final e in _estados.values) {
      e.cantidad.dispose();
      e.observacion.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    final lineas = <ConfirmacionLinea>[];
    for (final l in widget.pedido.lineas) {
      final e = _estados[l.id]!;
      final cantidad = _num(e.cantidad);
      if (cantidad == null) {
        setState(() => _error = 'Revisá la cantidad recibida de "${l.detalle}".');
        return;
      }
      lineas.add(ConfirmacionLinea(
        lineaId: l.id,
        recibidoOk: e.ok,
        cantidadRecibida: cantidad,
        observacion: e.observacion.text,
      ));
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error =
        await widget.servicio.confirmar(widget.pedido, lineas, nota: _nota.text);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Entrega confirmada.');
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
    final p = widget.pedido;
    return ModalFormulario(
      titulo: 'Confirmar entrega',
      icono: Icons.fact_check_outlined,
      textoBoton: 'Guardar conformidad',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Entregado por ${p.entregadoPorNombre ?? '—'} · '
              '${p.entregadoEn == null ? '' : fmtFechaHora(p.entregadoEn)}'),
          const SizedBox(height: 12),
          for (final l in p.lineas) _fila(l),
          const SizedBox(height: 12),
          TextField(
            controller: _nota,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Nota general (opcional)',
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }

  Widget _fila(LineaPedido l) {
    final e = _estados[l.id]!;
    return Card(
      elevation: 0,
      color: const Color(0xFFF5F7FA),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.detalle, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('Entregado: ${fmtNum(l.cantidadEntregada)} ${l.unidad}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            if (l.lotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Lotes: ${l.lotes.map((lo) => lo.nLote ?? 'sin lote').join(', ')}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: true, label: Text('Conforme')),
                      ButtonSegment(value: false, label: Text('Con problema')),
                    ],
                    selected: {e.ok},
                    onSelectionChanged: (s) => setState(() => e.ok = s.first),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: e.cantidad,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Recibido',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: e.observacion,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Observación',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
