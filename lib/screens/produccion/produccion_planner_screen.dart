import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/produccion_service.dart';

/// "Lo que el ingeniero organizó para el día": el Jefe de Producción
/// agrega cada sabor con sus litros planificados; al terminar de hacer
/// un sabor lo marca (como una lista de tareas) y el sistema descuenta
/// automáticamente la materia prima según la fórmula (trigger en BD).
class ProduccionPlannerScreen extends StatefulWidget {
  const ProduccionPlannerScreen({super.key});
  @override
  State<ProduccionPlannerScreen> createState() =>
      _ProduccionPlannerScreenState();
}

class _ProduccionPlannerScreenState extends State<ProduccionPlannerScreen> {
  PlanProduccion? _plan;
  List<Formula> _formulas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final usuario = context.read<AuthService>().usuarioActual!;
    final plan = await ProduccionService.planDeHoy(usuario.id);
    final formulas = await ProduccionService.listarFormulas();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _formulas = formulas;
      _cargando = false;
    });
  }

  Future<void> _agregarSabor() async {
    Formula? formula = _formulas.isNotEmpty ? _formulas.first : null;
    final litrosCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Agregar sabor al plan del día'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Formula>(
                value: formula,
                decoration: const InputDecoration(labelText: 'Sabor'),
                items: _formulas
                    .map((f) =>
                        DropdownMenuItem(value: f, child: Text(f.sabor)))
                    .toList(),
                onChanged: (v) => setLocal(() => formula = v),
              ),
              TextField(
                controller: litrosCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Litros a producir'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Agregar')),
          ],
        ),
      ),
    );

    if (ok == true && formula != null && litrosCtrl.text.isNotEmpty) {
      final usuario = context.read<AuthService>().usuarioActual!;
      await ProduccionService.agregarSaborAlPlan(
        planId: _plan!.id,
        formulaId: formula!.id,
        litros: double.tryParse(litrosCtrl.text) ?? 0,
        usuarioId: usuario.id,
      );
      _cargar();
    }
  }

  Future<void> _marcarCompletado(PlanProduccionDetalle d) async {
    final usuario = context.read<AuthService>().usuarioActual!;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Marcar como completado'),
        content: Text(
            'Se descontará automáticamente la materia prima de la fórmula '
            'de "${d.sabor}" según ${d.litrosPlanificados.toStringAsFixed(0)} L. '
            'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar == true) {
      await ProduccionService.marcarComoCompletado(
          detalleId: d.id, usuarioId: usuario.id);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    if (_cargando) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Producción del día',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (usuario.esAlmacen || usuario.esJefeProduccion)
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: _agregarSabor,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar sabor'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Marca cada sabor cuando termine de producirse: el sistema '
              'descuenta automáticamente azúcar, esencias y demás insumos '
              'según la fórmula registrada.',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Expanded(
            child: _plan == null || _plan!.detalle.isEmpty
                ? const Center(child: Text('Aún no hay sabores planificados hoy.'))
                : ListView(
                    children: _plan!.detalle
                        .map((d) => Card(
                              child: ListTile(
                                leading: Icon(
                                  d.completado
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: d.completado
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 32,
                                ),
                                title: Text(d.sabor,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    '${d.litrosPlanificados.toStringAsFixed(0)} litros planificados'),
                                trailing: d.completado
                                    ? const Chip(label: Text('Completado'))
                                    : ElevatedButton(
                                        onPressed: () => _marcarCompletado(d),
                                        child: const Text('Marcar hecho'),
                                      ),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
