import 'package:flutter/material.dart';

import '../../models/insumo_model.dart';
import '../../models/receta_model.dart';
import '../../models/usuario_model.dart';
import '../../services/database_service.dart';
import '../../services/inventario_logic_service.dart';

class _NecesidadCalculada {
  final String claveReceta;
  final double cantidadNecesaria;
  final InsumoModel? insumo;
  bool tickeado;

  _NecesidadCalculada({
    required this.claveReceta,
    required this.cantidadNecesaria,
    required this.insumo,
    this.tickeado = false,
  });
}

class PlanProduccionWidget extends StatefulWidget {
  final UsuarioModel usuario;

  const PlanProduccionWidget({super.key, required this.usuario});

  @override
  State<PlanProduccionWidget> createState() => _PlanProduccionWidgetState();
}

class _PlanProduccionWidgetState extends State<PlanProduccionWidget> {
  late Future<List<InsumoModel>> _insumosFuture;
  RecetaProducto? _productoSeleccionado;
  final _cantidadController = TextEditingController();
  List<_NecesidadCalculada>? _necesidades;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _insumosFuture = DatabaseService.fetchInsumos();
    _productoSeleccionado = RecetaCatalogo.recetas.first;
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }

  InsumoModel? _buscarInsumo(List<InsumoModel> insumos, String clave) {
    final claveNorm = clave.toLowerCase();
    for (final insumo in insumos) {
      if (insumo.nombre.toLowerCase().contains(claveNorm)) {
        return insumo;
      }
    }
    return null;
  }

  void _calcular(List<InsumoModel> insumos) {
    final producto = _productoSeleccionado;
    final unidades = int.tryParse(_cantidadController.text.trim()) ?? 0;
    if (producto == null || unidades <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese cuántas unidades va a producir.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final resultados = <_NecesidadCalculada>[];
    for (final entry in producto.insumosPorUnidad.entries) {
      final plan = InventarioLogicService.calcularPlanProduccion(
        unidadesObjetivo: unidades,
        rendimientoPorUnidad: entry.value,
        // 3% de merma / derrame estándar de línea de embotellado.
        desperdicio: 0.03,
      );
      final cantidad = InventarioLogicService.redondearCantidad(
        (plan['cantidad_total_requerida'] as num).toDouble(),
        decimales: 3,
      );
      resultados.add(
        _NecesidadCalculada(
          claveReceta: entry.key,
          cantidadNecesaria: cantidad,
          insumo: _buscarInsumo(insumos, entry.key),
        ),
      );
    }

    setState(() => _necesidades = resultados);
  }

  Future<void> _confirmarYDescontar() async {
    final necesidades = _necesidades;
    if (necesidades == null) return;

    final seleccionados = necesidades
        .where((n) => n.tickeado && n.insumo != null)
        .toList();

    if (seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tickee al menos un insumo ya retirado del almacén.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    final orden =
        'PROD-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${_productoSeleccionado!.producto}';

    var okTodos = true;
    for (final item in seleccionados) {
      final ok = await DatabaseService.registrarConsumoPlanta(
        ordenProduccion: orden,
        insumoId: item.insumo!.id,
        insumoNombre: item.insumo!.nombre,
        cantidadConsumida: item.cantidadNecesaria,
        operario: widget.usuario.nombre,
        usuarioId: widget.usuario.id,
      );
      if (!ok) okTodos = false;
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          okTodos
              ? 'Stock descontado para ${seleccionados.length} insumo(s) de "${_productoSeleccionado!.producto}".'
              : 'Se registró parcialmente: revise los insumos sin stock suficiente.',
        ),
        backgroundColor: okTodos ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<List<InsumoModel>>(
            future: _insumosFuture,
            builder: (context, snapshot) {
              final insumos = snapshot.data ?? <InsumoModel>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.precision_manufacturing_rounded,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Plan de Producción del Día',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Indique el sabor y cuántas unidades va a producir hoy: '
                      'el sistema calcula automáticamente la materia prima e '
                      'insumos necesarios.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<RecetaProducto>(
                            initialValue: _productoSeleccionado,
                            decoration: const InputDecoration(
                              labelText: 'Sabor / Producto',
                              prefixIcon: Icon(Icons.local_drink_outlined),
                            ),
                            items: RecetaCatalogo.recetas
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r.producto),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _productoSeleccionado = value;
                                _necesidades = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _cantidadController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Unidades a producir',
                              prefixIcon: Icon(Icons.numbers_outlined),
                            ),
                            onChanged: (_) => setState(() => _necesidades = null),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _calcular(insumos),
                        icon: const Icon(Icons.calculate_outlined),
                        label: const Text('Calcular necesidades'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_necesidades != null) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Vaya tickeando cada insumo a medida que lo retira del '
                        'almacén. Al confirmar, se descuenta el stock y queda '
                        'en la bitácora.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._necesidades!.map((item) {
                        final sinStock =
                            item.insumo == null;
                        final stockInsuficiente = item.insumo != null &&
                            item.insumo!.stockActual < item.cantidadNecesaria;
                        return CheckboxListTile(
                          value: item.tickeado,
                          onChanged: sinStock
                              ? null
                              : (checked) => setState(
                                  () => item.tickeado = checked ?? false,
                                ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(
                            item.insumo?.nombre ?? item.claveReceta,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            sinStock
                                ? 'No se encontró este insumo en el inventario cargado.'
                                : 'Necesita ${item.cantidadNecesaria} ${item.insumo!.unidadMedida} • '
                                      'Stock actual: ${item.insumo!.stockActual.toStringAsFixed(1)} ${item.insumo!.unidadMedida}'
                                      '${stockInsuficiente ? ' — INSUFICIENTE' : ''}',
                            style: TextStyle(
                              color: sinStock || stockInsuficiente
                                  ? Colors.red.shade700
                                  : Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _guardando
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                        const SizedBox(width: 12),
                        if (_necesidades != null)
                          FilledButton.icon(
                            onPressed: _guardando
                                ? null
                                : _confirmarYDescontar,
                            icon: _guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              _guardando
                                  ? 'Guardando...'
                                  : 'Confirmar y descontar stock',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
