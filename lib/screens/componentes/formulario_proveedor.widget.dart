import 'package:flutter/material.dart';

import '../../models/usuario_model.dart';
import '../../services/database_service.dart';

class FormularioProveedor extends StatefulWidget {
  final UsuarioModel usuario;

  const FormularioProveedor({super.key, required this.usuario});

  @override
  State<FormularioProveedor> createState() => _FormularioProveedorState();
}

class _FormularioProveedorState extends State<FormularioProveedor> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _rucController = TextEditingController();
  final _contactoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _correoController = TextEditingController();
  final _direccionController = TextEditingController();
  bool _guardando = false;

  Future<void> _guardarProveedor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final resultado = await DatabaseService.registrarProveedor(
        nombreEmpresa: _nombreController.text.trim(),
        ruc: _rucController.text.trim(),
        contacto: _contactoController.text.trim(),
        telefono: _telefonoController.text.trim(),
        correo: _correoController.text.trim(),
        catalogo: _direccionController.text.trim(),
        usuarioId: widget.usuario.id,
      );

      final ok = resultado['ok'] == true;

      if (!mounted) return;

      if (ok) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proveedor registrado correctamente.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se guardó la operación en modo offline.'),
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
                        Icons.business_rounded,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Registrar Proveedor',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del proveedor',
                      prefixIcon: Icon(Icons.business_center_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Requerido'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _rucController,
                    decoration: const InputDecoration(
                      labelText: 'RUC / Documento',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Requerido'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _contactoController,
                    decoration: const InputDecoration(
                      labelText: 'Contacto principal',
                      prefixIcon: Icon(Icons.person_outline),
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
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _correoController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Requerido';
                            }
                            if (!value.contains('@')) {
                              return 'Correo inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _direccionController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Catálogo / Dirección de referencia',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Requerido'
                        : null,
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
                        onPressed: _guardando ? null : _guardarProveedor,
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
                          _guardando ? 'Guardando...' : 'Guardar Proveedor',
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
