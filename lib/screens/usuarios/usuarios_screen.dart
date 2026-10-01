import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../core/constants.dart';
import '../../models/datos_empleado.dart';
import '../../services/auth_service.dart';
import '../../services/datos_empleado_service.dart';
import '../../services/supabase_service.dart';
import '../../shared/ayuda/tour_ayuda.dart';
import '../../utils/notificaciones.dart';
import 'usuario_form_dialog.dart';

/// Gestión de usuarios: solo el Gerente da de alta y edita usuarios (nombre,
/// correo, rol, área y estado). El resto de los roles (incluido Almacén)
/// solo ven la lista.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});
  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Map<String, dynamic>> _usuarios = [];
  Map<String, String> _correos = {};
  String? _avisoCorreos; // por qué no se pudieron traer los correos
  Map<String, DatosEmpleado> _datos = {};
  bool _datosDisponibles = false; // se pudo consultar la tabla de datos
  List<Map<String, dynamic>> _bloqueadas = []; // cuentas con bloqueo de login activo
  bool _cargando = true;

  final _pasoNuevoUsuario = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Nuevo usuario',
    texto: 'Al crear o editar un usuario elegís su rol; ahí mismo podés ver y ajustar '
        'los permisos de ese rol.',
  );
  final _pasoLista = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Lista de usuarios',
    texto: 'Tocá el lápiz para editar nombre, correo, rol, área o estado de un usuario.',
  );

  @override
  void initState() {
    super.initState();
    _cargar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'usuarios', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoNuevoUsuario, _pasoLista];

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final puedeAdministrar =
        context.read<AuthService>().usuarioActual?.puedeCrearUsuarios ?? false;
    List<Map<String, dynamic>> usuarios = [];
    final correos = <String, String>{};
    String? aviso;
    try {
      final data = await SupabaseService.client
          .from('usuarios')
          .select()
          .order('created_at')
          .timeout(SupabaseService.timeoutRed);
      usuarios = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      // Sin conexión: no hay caché de usuarios, se muestra la lista vacía.
    }
    if (puedeAdministrar) {
      try {
        // El correo vive en la cuenta de acceso: solo el Gerente lo obtiene,
        // y por una función del servidor.
        final data = await SupabaseService.client
            .rpc('usuarios_con_correo')
            .timeout(SupabaseService.timeoutRed);
        for (final f in List<Map<String, dynamic>>.from(data)) {
          correos[f['id'] as String] = f['email'] as String;
        }
      } catch (e) {
        aviso = (e is PostgrestException &&
                (e.code == 'PGRST202' || e.message.contains('Could not find the function')))
            ? 'No se pueden mostrar los correos: falta ejecutar '
                'schema_v14_roles_y_edicion_usuarios.sql en Supabase.'
            : 'No se pudieron cargar los correos (revisá la conexión).';
      }
    }
    var datos = <String, DatosEmpleado>{};
    var datosDisponibles = false;
    if (puedeAdministrar) {
      try {
        datos = await DatosEmpleadoService.obtenerTodos();
        datosDisponibles = true;
      } catch (_) {
        // Migración v15 sin aplicar o sin conexión: no se muestran los datos.
      }
    }
    var bloqueadas = <Map<String, dynamic>>[];
    if (puedeAdministrar) {
      try {
        final data = await SupabaseService.client
            .rpc('intentos_login_bloqueadas')
            .timeout(SupabaseService.timeoutRed);
        bloqueadas = List<Map<String, dynamic>>.from(data);
      } catch (_) {
        // Migración v23 sin aplicar o sin conexión: no se muestra el aviso.
      }
    }
    if (!mounted) return;
    setState(() {
      _datos = datos;
      _datosDisponibles = datosDisponibles;
      _usuarios = usuarios;
      _correos = correos;
      _avisoCorreos = aviso;
      _bloqueadas = bloqueadas;
      _cargando = false;
    });
  }

  Future<void> _desbloquear(String correo) async {
    try {
      await SupabaseService.client
          .rpc('intentos_login_desbloquear', params: {'p_email': correo})
          .timeout(SupabaseService.timeoutRed);
      if (mounted) mostrarExito(context, 'Se desbloqueó el acceso de $correo.');
      _cargar();
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo desbloquear. Revisá la conexión.');
    }
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? usuario}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => UsuarioFormDialog(
        usuario: usuario,
        correoActual: usuario != null ? _correos[usuario['id']] : null,
        avisoCorreo: _avisoCorreos,
        datosDisponibles: _datosDisponibles,
        datos: usuario != null ? _datos[usuario['id']] : null,
      ),
    );
    if (guardado == true) {
      if (mounted) {
        mostrarExito(context,
            usuario == null
                ? 'Usuario creado. Completará sus datos al ingresar.'
                : 'Cambios guardados.');
      }
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioActual = context.watch<AuthService>().usuarioActual!;
    final puedeAdministrar = usuarioActual.puedeCrearUsuarios;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Usuarios',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              BotonAyuda(idTour: 'usuarios', pasos: _pasosAyuda),
            ],
          ),
          if (puedeAdministrar) ...[
            const SizedBox(height: 12),
            _pasoNuevoUsuario.envolver(
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _abrirFormulario(),
                icon: const Icon(Icons.person_add),
                label: const Text('Nuevo usuario'),
              ),
            ),
          ],
          if (puedeAdministrar && _avisoCorreos != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                border: Border.all(color: const Color(0xFFF0C27B)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_avisoCorreos!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00))),
            ),
          ],
          if (puedeAdministrar && _bloqueadas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                border: Border.all(color: const Color(0xFFEFA0A0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Accesos bloqueados por intentos fallidos',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB03030))),
                  const SizedBox(height: 6),
                  for (final b in _bloqueadas)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${b['nombre_completo'] ?? b['correo']} (${b['correo']})'
                              '${b['permanente'] == true ? ' · bloqueo permanente' : ' · temporal'}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF8A2020)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFFB03030)),
                            onPressed: () => _desbloquear(b['correo'] as String),
                            child: const Text('Desbloquear'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _pasoLista.envolver(
              _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = _usuarios[i];
                      final activo = u['activo'] ?? true;
                      final nombre = (u['nombre_completo'] ?? '') as String;
                      final rolNombre = Rol.etiqueta(u['rol'] ?? '');
                      final correo = _correos[u['id']];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              activo ? Colors.green.shade100 : Colors.grey.shade300,
                          backgroundImage: u['avatar_url'] != null
                              ? NetworkImage(u['avatar_url'])
                              : null,
                          child: u['avatar_url'] == null
                              ? Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                                child: Text(nombre, overflow: TextOverflow.ellipsis)),
                            if (puedeAdministrar &&
                                _datosDisponibles &&
                                activo &&
                                !(_datos[u['id']]?.completo ?? false)) ...[
                              const SizedBox(width: 8),
                              const Chip(
                                label: Text('Datos pendientes'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Color(0xFFFFF4E5),
                                labelStyle:
                                    TextStyle(fontSize: 11, color: Color(0xFF8A5A00)),
                              ),
                            ],
                            if (!activo) ...[
                              const SizedBox(width: 8),
                              const Chip(
                                label: Text('Inactivo'),
                                visualDensity: VisualDensity.compact,
                                labelStyle: TextStyle(fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                            correo != null ? '$rolNombre · $correo' : rolNombre),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (puedeAdministrar)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: 'Editar usuario',
                                onPressed: () => _abrirFormulario(usuario: u),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
