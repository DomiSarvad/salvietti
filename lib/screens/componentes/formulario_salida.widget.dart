import 'package:flutter/material.dart';

import '../../models/insumo_model.dart';
import '../../models/usuario_model.dart';
import '../../services/database_service.dart';

class FormularioSalidaInsumo extends StatefulWidget {
  final UsuarioModel usuario;

  const FormularioSalidaInsumo({super.key, required this.usuario});

  @override
  State<FormularioSalidaInsumo> createState() => _FormularioSalidaInsumoState();
}

class _FormularioSalidaInsumoState extends State<FormularioSalidaInsumo> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _areaController = TextEditingController();
  final _motivoController = TextEditingController();
  final _loteController = TextEditingController();

  late Future<List<InsumoModel>> _insumosFuture;
  InsumoModel? _insumoSeleccionado;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _insumosFuture = DatabaseService.fetchInsumos();
  }

  Future<void> _guardarSalida() async {
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
      final ok = await DatabaseService.registrarSalida(
        insumoId: _insumoSeleccionado!.id,
        usuarioId: widget.usuario.id,
        areaDestino: _areaController.text.trim().isEmpty
            ? 'Almacén general'
            : _areaController.text.trim(),
        cantidadSolicitada: cantidad,
        unidadMedida: _insumoSeleccionado!.unidadMedida,
        numeroLote: _loteController.text.trim().isEmpty
            ? _insumoSeleccionado!.numeroLote
            : _loteController.text.trim(),
        motivo: _motivoController.text.trim().isEmpty
            ? 'Salida de almacén'
            : _motivoController.text.trim(),
        insumoNombre: _insumoSeleccionado!.nombre,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salida registrada correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La salida quedó registrada en local. Se sincronizará luego.',
            ),
            backgroundColor: Colors.orange,
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
                            Icons.output_rounded,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Salida de inventario',
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
                                  '${insumo.nombre} • stock ${insumo.stockActual} ${insumo.unidadMedida}',
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
                                labelText: 'Cantidad a sacar',
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
                                labelText: 'Área o destino',
                                prefixIcon: Icon(Icons.location_on_outlined),
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
                        controller: _motivoController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Motivo de salida',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _loteController,
                        decoration: const InputDecoration(
                          labelText: 'Lote / referencia',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
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
                            onPressed: _guardando ? null : _guardarSalida,
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
                              _guardando ? 'Guardando...' : 'Registrar salida',
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
