import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

/// Gestión de usuarios: el Gerente puede AGREGAR usuarios (con permiso),
/// pero solo Almacén tiene control total (editar rol/activar-desactivar).
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});
  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Map<String, dynamic>> _usuarios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await SupabaseService.client
        .from('usuarios')
        .select()
        .order('created_at');
    if (!mounted) return;
    setState(() {
      _usuarios = List<Map<String, dynamic>>.from(data);
      _cargando = false;
    });
  }

  Future<void> _nuevoUsuario() async {
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    String rol = Rol.jarabes;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo usuario'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nombreCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo')),
                TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Correo')),
                TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Contraseña temporal')),
                DropdownButtonFormField<String>(
                  value: rol,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: Rol.todos
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(Rol.etiqueta(r))))
                      .toList(),
                  onChanged: (v) => setLocal(() => rol = v!),
                ),
                if (rol == Rol.jarabes)
                  TextField(
                      controller: areaCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Área (ej. Jarabes)')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final auth = context.read<AuthService>();
      final error = await auth.crearUsuario(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
        nombreCompleto: nombreCtrl.text.trim(),
        rol: rol,
        area: areaCtrl.text.isEmpty ? null : areaCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error ?? 'Usuario creado correctamente.')));
      }
      if (error == null) _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioActual = context.watch<AuthService>().usuarioActual!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Usuarios',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (usuarioActual.puedeCrearUsuarios)
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: _nuevoUsuario,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Nuevo usuario'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = _usuarios[i];
                      return ListTile(
                        leading: CircleAvatar(
                            backgroundColor:
                                (u['activo'] ?? true) ? Colors.green.shade100 : Colors.grey.shade300,
                            child: Text((u['nombre_completo'] ?? '?')[0])),
                        title: Text(u['nombre_completo'] ?? ''),
                        subtitle: Text(Rol.etiqueta(u['rol'] ?? '')),
                        trailing: (u['area'] != null)
                            ? Chip(label: Text(u['area']))
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
