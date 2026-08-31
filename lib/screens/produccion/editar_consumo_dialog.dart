import 'package:flutter/material.dart';
import '../../models/insumo.dart';
import '../../models/produccion.dart';
import '../../services/inventario_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/responsive.dart';

/// Una fila editable de la receta: qué materia prima y cuánta se gasta
/// por lote base del sabor.
class _FilaReceta {
  Insumo? materiaPrima;
  final TextEditingController cantidadCtrl;
  _FilaReceta({this.materiaPrima, String cantidadInicial = ''})
      : cantidadCtrl = TextEditingController(text: cantidadInicial);
}

/// "Editar consumo": para que el Jefe de Producción ajuste, por sabor,
/// cuánta materia prima se gasta por lote (lo que hoy son valores
/// supuestos cargados como ejemplo). Por ahora es simple y funcional:
/// elegir el sabor, ver/editar sus insumos y cantidades, y guardar.
class EditarConsumoDialog extends StatefulWidget {
  const EditarConsumoDialog({super.key});
  @override
  State<EditarConsumoDialog> createState() => _EditarConsumoDialogState();
}

class _EditarConsumoDialogState extends State<EditarConsumoDialog> {
  List<Formula> _formulas = [];
  List<Insumo> _materiaPrima = [];
  Formula? _formulaSeleccionada;
  final _rendimientoCtrl = TextEditingController(text: '100');
  List<_FilaReceta> _filas = [];
  bool _cargando = true;
  bool _cargandoDetalle = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarInicial();
  }

  Future<void> _cargarInicial() async {
    final formulas = await ProduccionService.listarFormulas();
    final materiaPrima = await InventarioService.listar('materia_prima');
    if (!mounted) return;
    setState(() {
      _formulas = formulas;
      _materiaPrima = materiaPrima;
      _cargando = false;
    });
  }

  Future<void> _elegirFormula(Formula f) async {
    setState(() {
      _formulaSeleccionada = f;
      _rendimientoCtrl.text = f.rendimientoLitros.toStringAsFixed(0);
      _cargandoDetalle = true;
      _filas = [];
    });
    final detalle = await ProduccionService.listarFormulaDetalle(f.id);
    if (!mounted) return;
    setState(() {
      _filas = detalle
          .map((d) => _FilaReceta(
                materiaPrima: _materiaPrima
                    .where((m) => m.id == d['materia_prima_id'])
                    .firstOrNull,
                cantidadInicial: '${d['cantidad_por_lote']}',
              ))
          .toList();
      _cargandoDetalle = false;
    });
  }

  void _agregarFila() => setState(() => _filas.add(_FilaReceta()));

  void _quitarFila(int i) => setState(() => _filas.removeAt(i));

  Future<void> _guardar() async {
    if (_formulaSeleccionada == null) return;
    final detalle = <Map<String, dynamic>>[];
    for (final fila in _filas) {
      final cantidad = double.tryParse(fila.cantidadCtrl.text);
      if (fila.materiaPrima == null || cantidad == null || cantidad <= 0) {
        continue; // filas incompletas se ignoran en vez de romper el guardado
      }
      detalle.add({
        'materia_prima_id': fila.materiaPrima!.id,
        'cantidad_por_lote': cantidad,
      });
    }
    final rendimiento = double.tryParse(_rendimientoCtrl.text);
    if (rendimiento == null || rendimiento <= 0) {
      setState(() => _error = 'El rendimiento (litros por lote) debe ser mayor a 0.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ProduccionService.guardarFormula(
        formulaId: _formulaSeleccionada!.id,
        sabor: _formulaSeleccionada!.sabor,
        rendimientoLitros: rendimiento,
        detalle: detalle,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar consumo por producto'),
      content: SizedBox(
        width: anchoDialogo(context, 460),
        height: 480,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Elegí un sabor para ver y ajustar cuánto se gasta de '
                      'cada insumo por cada lote base (litros indicados abajo).',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Formula>(
                    value: _formulaSeleccionada,
                    decoration: const InputDecoration(labelText: 'Sabor'),
                    items: _formulas
                        .map((f) => DropdownMenuItem(value: f, child: Text(f.sabor)))
                        .toList(),
                    onChanged: (f) {
                      if (f != null) _elegirFormula(f);
                    },
                  ),
                  if (_formulaSeleccionada != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _rendimientoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Rendimiento del lote (litros)'),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _cargandoDetalle
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              children: [
                                ..._filas.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final fila = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: DropdownButtonFormField<Insumo>(
                                            value: fila.materiaPrima,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Insumo'),
                                            items: _materiaPrima
                                                .map((m) => DropdownMenuItem(
                                                    value: m,
                                                    child: Text(m.detalle,
                                                        overflow:
                                                            TextOverflow.ellipsis)))
                                                .toList(),
                                            onChanged: (m) => setState(
                                                () => fila.materiaPrima = m),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: fila.cantidadCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                                labelText: fila.materiaPrima
                                                        ?.unidadMedida ??
                                                    'Cantidad'),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 20, color: Colors.red),
                                          onPressed: () => _quitarFila(i),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                TextButton.icon(
                                  onPressed: _agregarFila,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Agregar insumo'),
                                ),
                              ],
                            ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
        if (_formulaSeleccionada != null)
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
