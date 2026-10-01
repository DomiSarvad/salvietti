import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/datos_empleado.dart';
import '../../services/auth_service.dart';
import '../../services/datos_empleado_service.dart';
import '../../utils/responsive.dart';
import '../../features/permisos/screens/permisos_screen.dart';
import '../../widgets/campos_datos_empleado.dart';
import '../../widgets/dialog_banner.dart';
import '../../widgets/selector_rol.dart';

/// Alta y edición de usuarios (solo Gerente). En edición se pueden cambiar
/// nombre, correo, rol, área y si la cuenta está activa; la contraseña no
/// (para eso está "¿Olvidaste tu contraseña?" y el cambio desde el perfil).
/// El rol se elige en un desplegable con buscador entre los 4 roles del
/// sistema (crear roles nuevos queda como mejora futura).
class UsuarioFormDialog extends StatefulWidget {
  /// Fila de la tabla `usuarios` a editar; null = alta de un usuario nuevo.
  final Map<String, dynamic>? usuario;
  final String? correoActual;
  /// Por qué no se pudo traer el correo actual (si pasó); se muestra bajo el campo.
  final String? avisoCorreo;

  /// Datos personales del empleado (si ya los completó) y si se pudo consultar
  /// esa tabla; el Gerente puede completarlos o corregirlos desde acá.
  final DatosEmpleado? datos;
  final bool datosDisponibles;
  const UsuarioFormDialog({
    super.key,
    this.usuario,
    this.correoActual,
    this.avisoCorreo,
    this.datos,
    this.datosDisponibles = false,
  });

  @override
  State<UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends State<UsuarioFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  final _passCtrl = TextEditingController();
  late final DatosEmpleadoCtrl _datosCtrl;
  String? _rol; // id del rol (almacen, gerente, jefe_produccion, jarabes)
  late bool _activo;
  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.usuario != null;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _nombreCtrl = TextEditingController(text: u?['nombre_completo'] ?? '');
    _emailCtrl = TextEditingController(text: widget.correoActual ?? '');
    _activo = u?['activo'] ?? true;
    _datosCtrl = DatosEmpleadoCtrl(widget.datos);
    if (u != null) _rol = u['rol'] as String?;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _datosCtrl.dispose();
    super.dispose();
  }

  bool get _esUnoMismo =>
      _esEdicion &&
      widget.usuario!['id'] == context.read<AuthService>().usuarioActual?.id;

  Future<void> _elegirRol() async {
    final r = await elegirRol(context, actual: _rol);
    if (r != null) setState(() => _rol = r);
  }

  /// Abre "Permisos por rol" ya con este rol elegido — así, al editar o dar
  /// de alta a alguien, el Gerente puede revisar o ajustar en el momento
  /// qué puede hacer ese rol, sin ir a buscarlo a otro lado.
  void _verPermisos() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text('Permisos de ${Rol.etiqueta(_rol!)}'),
          backgroundColor: AppColors.primario,
          foregroundColor: Colors.white,
        ),
        body: PermisosScreen(rolInicial: _rol),
      ),
    ));
  }

  Future<void> _guardar() async {
    if (_rol == null) {
      setState(() => _error = 'Elegí un rol.');
      return;
    }
    final datos = _datosCtrl.toDatos();
    final mostrarDatos = _esEdicion && widget.datosDisponibles;
    if (mostrarDatos) {
      // El Gerente puede dejar datos incompletos (el empleado los termina),
      // pero lo que escriba tiene que tener formato válido.
      final e = datos.validar(obligatorios: false);
      if (e != null) {
        setState(() => _error = e);
        return;
      }
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = _esEdicion
        ? await auth.editarUsuario(
            id: widget.usuario!['id'] as String,
            email: _emailCtrl.text,
            nombreCompleto: _nombreCtrl.text,
            rol: _rol!,
            activo: _activo,
          )
        : await auth.crearUsuario(
            email: _emailCtrl.text,
            password: _passCtrl.text,
            nombreCompleto: _nombreCtrl.text,
            rol: _rol!,
          );
    if (!mounted) return;
    if (error == null && mostrarDatos) {
      final hayDatos = datos.celular?.trim().isNotEmpty == true ||
          datos.carnet?.trim().isNotEmpty == true ||
          datos.direccion?.trim().isNotEmpty == true ||
          datos.fechaNacimiento != null ||
          datos.fechaIngreso != null;
      if (hayDatos || widget.datos != null) {
        try {
          await DatosEmpleadoService.guardar(
              widget.usuario!['id'] as String, datos, comoGerente: true);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _guardando = false;
            _error = 'Se guardó el usuario, pero no se pudieron guardar sus datos '
                'personales. Revisá la conexión e intentá de nuevo.';
          });
          return;
        }
      }
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label, IconData icono) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, size: 20),
        filled: true,
        fillColor: const Color(0xFFF4F6F8),
        counterText: '',
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final nombre = _nombreCtrl.text.trim();
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : null;
    final esUnoMismo = _esUnoMismo;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogBanner(
                onCerrar: () => Navigator.pop(context, false),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration:
                      const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0x1A1B5E3A),
                    child: _esEdicion && inicial != null
                        ? Text(inicial,
                            style: const TextStyle(
                                fontSize: 32, color: AppColors.primario))
                        : Icon(_esEdicion ? Icons.manage_accounts : Icons.person_add_alt_1,
                            size: 40, color: AppColors.primario),
                  ),
                ),
              ),
              const SizedBox(height: 46),
              DialogRibbon(
                  texto: nombre.isEmpty
                      ? (_esEdicion ? 'Editar usuario' : 'Nuevo usuario')
                      : nombre),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nombreCtrl,
                      maxLength: 120,
                      onChanged: (_) => setState(() {}),
                      decoration: _deco('Nombre completo', Icons.badge_outlined),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _emailCtrl,
                      maxLength: Validacion.emailMax,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _deco('Correo', Icons.mail_outline),
                    ),
                    if (_esEdicion && widget.correoActual == null && widget.avisoCorreo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(widget.avisoCorreo!,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFD97706))),
                      ),
                    if (!_esEdicion) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: _passCtrl,
                        obscureText: true,
                        maxLength: Validacion.passwordMax,
                        decoration: _deco('Contraseña temporal', Icons.lock_outline),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Rol: desplegable con buscador entre los roles del sistema.
                    InkWell(
                      onTap: esUnoMismo ? null : _elegirRol,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _deco('Rol', Icons.workspace_premium_outlined)
                            .copyWith(
                                suffixIcon: const Icon(Icons.arrow_drop_down)),
                        child: Text(
                          _rol != null ? Rol.etiqueta(_rol!) : 'Elegí un rol',
                          style: TextStyle(
                              color: _rol == null ? Colors.black45 : Colors.black87),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              esUnoMismo
                                  ? 'No podés cambiar tu propio rol.'
                                  : 'Los permisos dependen del rol.',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ),
                          if (_rol != null)
                            TextButton.icon(
                              onPressed: _verPermisos,
                              icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                              label: const Text('Ver permisos', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            ),
                        ],
                      ),
                    ),
                    if (_esEdicion) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _activo,
                        activeThumbColor: AppColors.primario,
                        onChanged: esUnoMismo ? null : (v) => setState(() => _activo = v),
                        title: const Text('Cuenta activa'),
                        subtitle: Text(
                            esUnoMismo
                                ? 'No podés desactivar tu propia cuenta.'
                                : 'Si se desactiva, no puede iniciar sesión.',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                    if (_esEdicion && widget.datosDisponibles) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                      const Text('Datos del empleado',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        widget.datos?.completo == true
                            ? 'El empleado ya completó sus datos.'
                            : 'Los completa el propio empleado al ingresar; también podés cargarlos vos.',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      CamposDatosEmpleado(
                        ctrl: _datosCtrl,
                        mostrarFechaIngreso: true,
                        fechaIngresoEditable: true,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDECEA),
                          border: Border.all(color: const Color(0xFFF5C2BE)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Color(0xFFB3261E), fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                // OverflowBar, no Row: sin un Expanded, "Cancelar" + "Guardar
                // cambios" no siempre entran en el ancho del diálogo en un
                // teléfono angosto — se apilan en vertical solo si hace falta.
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                        onPressed: _guardando ? null : () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                      onPressed: _guardando ? null : _guardar,
                      child: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_esEdicion ? 'Guardar cambios' : 'Crear'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
