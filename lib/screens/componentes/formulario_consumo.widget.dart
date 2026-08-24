import 'package:flutter/material.dart';

import '../../models/insumo_model.dart';
import '../../models/usuario_model.dart';
import '../../services/database_service.dart';

class FormularioConsumoPlanta extends StatefulWidget {
  final UsuarioModel usuario;

  const FormularioConsumoPlanta({super.key, required this.usuario});

  @override
  State<FormularioConsumoPlanta> createState() =>
      _FormularioConsumoPlantaState();
}

class _FormularioConsumoPlantaState extends State<FormularioConsumoPlanta> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _observacionController = TextEditingController();
  final _areaController = TextEditingController();

  late Future<List<InsumoModel>> _insumosFuture;
  InsumoModel? _insumoSeleccionado;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _insumosFuture = DatabaseService.fetchInsumos();
  }

  Future<void> _guardarConsumo() async {
    if (!_formKey.currentState!.validate()) return;
    if (_insumoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un insumo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final cantidad = double.tryParse(_cantidadController.text.trim()) ?? 0;

      final ok = await DatabaseService.registrarConsumoPlanta(
        ordenProduccion: _areaController.text.trim().isEmpty
            ? 'OP-${DateTime.now().millisecondsSinceEpoch}'
            : _areaController.text.trim(),
        insumoId: _insumoSeleccionado!.id,
        insumoNombre: _insumoSeleccionado!.nombre,
        cantidadConsumida: cantidad,
        operario: widget.usuario.nombre,
        usuarioId: widget.usuario.id,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consumo de planta registrado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay stock suficiente para ese consumo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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

              return Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.local_shipping_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Consumo en Planta',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<InsumoModel>(
                        initialValue:
                            _insumoSeleccionado ??
                            (insumos.isNotEmpty ? insumos.first : null),
                        decoration: const InputDecoration(
                          labelText: 'Insumo',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        items: insumos
                            .map(
                              (insumo) => DropdownMenuItem<InsumoModel>(
                                value: insumo,
                                child: Text(
                                  '${insumo.nombre} (${insumo.unidadMedida})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _insumoSeleccionado = value);
                          }
                        },
                        validator: (value) =>
                            value == null ? 'Seleccione un insumo' : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cantidadController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad consumida',
                                prefixIcon: Icon(Icons.numbers_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                final cantidad = double.tryParse(value);
                                if (cantidad == null || cantidad <= 0) {
                                  return 'Cantidad inválida';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _areaController,
                              decoration: const InputDecoration(
                                labelText: 'Área / Línea',
                                prefixIcon: Icon(
                                  Icons.precision_manufacturing_outlined,
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Requerido'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _observacionController,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Observación / Motivo',
                          prefixIcon: Icon(Icons.comment_outlined),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _guardando
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _guardando ? null : _guardarConsumo,
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
                              _guardando ? 'Guardando...' : 'Registrar Consumo',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
