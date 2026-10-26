import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/produccion.dart';
import '../../../services/auth_service.dart';
import '../../../services/produccion_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../utils/texto.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/jarabes_modelos.dart';
import '../services/jarabes_service.dart';

/// Cierra un preparado en curso: hora de fin automática, Brix (obligatorio;
/// se lo pasa a Calidad para su análisis) y observaciones.
class FinalizarPreparadoDialog extends StatefulWidget {
  final JarabesService servicio;
  final Preparado preparado;
  /// El plan de hoy (Producción, subsistema aparte), si se pudo cargar: al
  /// finalizar, si hay un producto de ese sabor todavía sin marcar, se
  /// completa solo — así no hay que ir a Producción a tildarlo a mano.
  final PlanProduccion? planHoy;
  const FinalizarPreparadoDialog(
      {super.key, required this.servicio, required this.preparado, this.planHoy});

  @override
  State<FinalizarPreparadoDialog> createState() => _FinalizarPreparadoDialogState();
}

class _FinalizarPreparadoDialogState extends State<FinalizarPreparadoDialog> {
  final _brix = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _brix.dispose();
    _obs.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final brix = double.tryParse(_brix.text.trim().replaceAll(',', '.'));
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio
        .finalizarPreparado(widget.preparado, brix: brix, observaciones: _obs.text);
    if (!mounted) return;
    if (error == null) {
      final marcado = await _completarPlanSiCorresponde();
      if (!mounted) return;
      mostrarExito(context,
          marcado ? 'Preparado finalizado y marcado en el plan de hoy.' : 'Preparado finalizado.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  /// Si el sabor de este preparado está en el plan de hoy y ese producto
  /// todavía no está marcado, lo completa solo — con las botellas
  /// planificadas (dato oficial) como estimación, igual que ya hace el
  /// diálogo "Marcar hecho" de Producción por defecto. Se puede corregir
  /// después desde ahí si la cantidad real de botellas fue otra. No avisa
  /// error si algo falla acá: cerrar el preparado de Jarabes no debe
  /// depender de este paso extra.
  Future<bool> _completarPlanSiCorresponde() async {
    final plan = widget.planHoy;
    final sabor = widget.preparado.sabor;
    if (plan == null || sabor == null) return false;
    final buscado = sinTildes(sabor);
    PlanProduccionDetalle? detalle;
    for (final d in plan.detalle) {
      if (!d.completado && sinTildes(d.sabor) == buscado) {
        detalle = d;
        break;
      }
    }
    if (detalle == null) return false;
    final litros = widget.preparado.litros ?? detalle.litrosPlanificados;
    final litrosPorBotella = detalle.litrosPorBotella;
    if (litrosPorBotella == null || litrosPorBotella <= 0) return false;
    final botellas = (litros / litrosPorBotella).round().toDouble();
    try {
      final usuario = context.read<AuthService>().usuarioActual!;
      await ProduccionService.marcarComoCompletado(
        detalleId: detalle.id,
        usuarioId: usuario.id,
        botellasProducidas: botellas,
        litrosProducidos: litros,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preparado;
    return ModalFormulario(
      titulo: 'Finalizar preparado',
      icono: Icons.stop_circle_outlined,
      textoBoton: 'Finalizar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${p.sabor ?? ''} · ${p.sinSubir ? 'Lote al subir' : 'Lote ${p.nLote}'}${p.tanque == null ? '' : ' · Tanque ${p.tanque}'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('Inicio: ${fmtFechaHora(p.horaInicio)}'
              '${p.litros == null ? '' : ' · ${fmtNum(p.litros, decimales: 0)} L'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 16),
          TextField(
            controller: _brix,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Brix',
              helperText: 'Se lo pasa a Control de Calidad para su análisis',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obs,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observaciones (opcional)',
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
}
