import 'package:flutter/material.dart';

import '../../models/usuario_model.dart';
import '../../services/database_service.dart';

class FormularioEntradaInsumo extends StatefulWidget {
  final UsuarioModel usuario;

  const FormularioEntradaInsumo({super.key, required this.usuario});

  @override
  State<FormularioEntradaInsumo> createState() =>
      _FormularioEntradaInsumoState();
}

class _FormularioEntradaInsumoState extends State<FormularioEntradaInsumo> {
  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _loteController = TextEditingController();
  final _proveedorController = TextEditingController();

  String _unidadMedida = 'KG';
  DateTime? _fechaVencimiento;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _codigoController.text = _generarCodigoAutomatico();
  }

  String _generarCodigoAutomatico() {
    final fecha = DateTime.now();
    final random = (fecha.millisecondsSinceEpoch % 9000) + 1000;
    return 'MP-${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}-${random.toString()}';
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (picked != null) {
      setState(() => _fechaVencimiento = picked);
    }
  }

  Future<void> _guardarEntrada() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaVencimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar la fecha de vencimiento.'),
          backgroundColor: Colors.deepOrange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final ok = await DatabaseService.registrarEntradaMateriaPrima(
        codigoInsumo: _codigoController.text.trim(),
        descripcion: _descripcionController.text.trim(),
        cantidad: double.tryParse(_cantidadController.text.trim()) ?? 0,
        unidadMedida: _unidadMedida,
        numeroLote: _loteController.text.trim(),
        fechaVencimiento: _fechaVencimiento!,
        proveedorId: _proveedorController.text.trim(),
        usuarioId: widget.usuario.id,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro guardado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Modo Offline Activo. Datos protegidos localmente en la laptop.',
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
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Entrada de Materia Prima',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codigoController,
                          decoration: const InputDecoration(
                            labelText: 'Código de Insumo',
                            prefixIcon: Icon(Icons.qr_code_2_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _unidadMedida,
                          decoration: const InputDecoration(
                            labelText: 'Unidad',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'KG', child: Text('KG')),
                            DropdownMenuItem(value: 'PZA', child: Text('PZA')),
                            DropdownMenuItem(value: 'L', child: Text('L')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _unidadMedida = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descripcionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Detalle',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Requerido'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cantidadController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                            prefixIcon: Icon(Icons.numbers_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Requerido';
                            }
                            if (double.tryParse(value) == null ||
                                (double.tryParse(value) ?? 0) <= 0) {
                              return 'Cantidad inválida';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _loteController,
                          decoration: const InputDecoration(
                            labelText: 'Número de Lote',
                            prefixIcon: Icon(
                              Icons.confirmation_number_outlined,
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
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _seleccionarFecha,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha de Vencimiento',
                              prefixIcon: Icon(Icons.calendar_today_outlined),
                            ),
                            child: Text(
                              _fechaVencimiento == null
                                  ? 'Seleccionar fecha'
                                  : '${_fechaVencimiento!.day}/${_fechaVencimiento!.month}/${_fechaVencimiento!.year}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _proveedorController,
                          decoration: const InputDecoration(
                            labelText: 'Proveedor Asociado',
                            prefixIcon: Icon(Icons.business_center_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                    ],
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
                        onPressed: _guardando ? null : _guardarEntrada,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt_rounded),
                        label: Text(
                          _guardando ? 'Guardando...' : 'Confirmar Registro',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
