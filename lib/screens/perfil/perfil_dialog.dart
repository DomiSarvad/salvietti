import 'dart:async';
import 'dart:typed_data' show Uint8List;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../core/constants.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/datos_empleado_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';
import '../../utils/notificaciones.dart';
import '../../widgets/campos_datos_empleado.dart';
import '../../widgets/dialog_banner.dart';
import '../../shared/visor_foto.dart';

/// La cámara solo tiene sentido en móvil: en escritorio/web `image_picker`
/// no la soporta y siempre conviene ir directo al selector de archivos.
bool _hayCamaraDisponible() {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// "Mi perfil": foto y nombre visible, editables por cualquier usuario
/// (al estilo de una cuenta de Google), más un cambio de contraseña —
/// las dos cosas conviven como pestañas del mismo diálogo, con un banner
/// con degradado de marca y la foto superpuesta (mismo lenguaje visual
/// que "Nuevo usuario", ver [NuevoUsuarioDialog]).
/// El rol y el estado activo NUNCA se pueden tocar desde acá — eso sigue
/// siendo exclusivo de Gerente en la pantalla de Usuarios.
class PerfilDialog extends StatefulWidget {
  const PerfilDialog({super.key});

  @override
  State<PerfilDialog> createState() => _PerfilDialogState();
}

class _PerfilDialogState extends State<PerfilDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _nombreCtrl;
  final _nuevaCtrl = TextEditingController();
  final _datosCtrl = DatosEmpleadoCtrl();
  bool _cargandoDatos = true;
  final _confirmarCtrl = TextEditingController();

  bool _subiendoFoto = false;
  bool _guardando = false;
  String? _error;
  String? _avatarUrlActual;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() => _error = null));
    final usuario = context.read<AuthService>().usuarioActual!;
    _nombreCtrl = TextEditingController(text: usuario.nombreCompleto);
    _avatarUrlActual = usuario.avatarUrl;
    _cargarDatosPersonales(usuario.id);
  }

  Future<void> _cargarDatosPersonales(String usuarioId) async {
    try {
      final d = await DatosEmpleadoService.obtener(usuarioId);
      if (d != null && mounted) {
        _datosCtrl.celular.text = d.celular ?? '';
        _datosCtrl.carnet.text = d.carnet ?? '';
        _datosCtrl.direccion.text = d.direccion ?? '';
        _datosCtrl.fechaNacimiento = d.fechaNacimiento;
        _datosCtrl.fechaIngreso = d.fechaIngreso;
      }
    } catch (_) {
      // Sin conexión o tabla inexistente: se muestran los campos vacíos.
    }
    if (mounted) setState(() => _cargandoDatos = false);
  }

  Future<void> _guardarDatosPersonales() async {
    final datos = _datosCtrl.toDatos();
    final error = datos.validar(obligatorios: true);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await DatosEmpleadoService.guardar(
          context.read<AuthService>().usuarioActual!.id, datos);
      if (!mounted) return;
      mostrarExito(context, 'Datos personales guardados.');
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudieron guardar tus datos. Revisá tu conexión e intentá de nuevo.';
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nombreCtrl.dispose();
    _datosCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  /// Deja elegir entre cámara y galería (solo se ofrece cámara en
  /// móvil, donde tiene sentido). Devuelve null si el usuario cancela.
  Future<ImageSource?> _elegirOrigen() {
    final conCamara = _hayCamaraDisponible();
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conCamara)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(conCamara ? 'Elegir de galería' : 'Elegir una foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cambiarFoto(Usuario usuario) async {
    setState(() => _error = null);
    final origen = await _elegirOrigen();
    if (origen == null || !mounted) return;

    XFile? archivo;
    try {
      archivo = await ImagePicker().pickImage(
        source: origen,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final esCamara = origen == ImageSource.camera;
      final esPermiso = e.code.toLowerCase().contains('permission') ||
          e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied';
      setState(() => _error = esPermiso
          ? 'No hay permiso para usar ${esCamara ? "la cámara" : "tus fotos"}. '
              'Habilítalo en la configuración del sistema para esta app e inténtalo de nuevo.'
          : 'No se pudo abrir ${esCamara ? "la cámara" : "el selector de fotos"}: ${e.message ?? e.code}.');
      return;
    }
    if (archivo == null) return;

    setState(() => _subiendoFoto = true);
    try {
      final bytes = await archivo.readAsBytes();
      final ext = archivo.name.contains('.') ? archivo.name.split('.').last : 'jpg';
      final ruta = '${usuario.id}/avatar.$ext';

      await SupabaseService.client.storage.from('avatars').uploadBinary(
            ruta,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: archivo.mimeType,
            ),
          );
      final urlPublica = SupabaseService.client.storage
          .from('avatars')
          .getPublicUrl(ruta);
      // Cache-busting: la ruta no cambia al reemplazar la foto, así que
      // sin esto se seguiría viendo la imagen vieja cacheada.
      final url = '$urlPublica?t=${DateTime.now().millisecondsSinceEpoch}';

      if (!mounted) return;
      final auth = context.read<AuthService>();
      final error = await auth.actualizarPerfil(avatarUrl: url);
      if (!mounted) return;
      setState(() {
        _error = error;
        if (error == null) _avatarUrlActual = url;
      });
    } catch (_) {
      // Sin conexión (u otro error de red): no se pierde la foto elegida.
      // Se guarda localmente y se muestra de inmediato; el propio sistema
      // la sube sola en cuanto detecte conexión (SyncService).
      if (!mounted) return;
      final ext = archivo.name.contains('.') ? archivo.name.split('.').last : 'jpg';
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      await context.read<AuthService>().guardarFotoOffline(bytes, ext);
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sin conexión: la foto se guardó en el dispositivo '
              'y se subirá sola cuando haya internet.')));
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  Future<void> _guardarNombre() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.actualizarPerfil(nombreCompleto: _nombreCtrl.text);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _guardarPassword() async {
    if (_nuevaCtrl.text != _confirmarCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.cambiarPassword(_nuevaCtrl.text);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contraseña actualizada correctamente.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuarioActual!;
    final fotoPendiente = auth.fotoLocalPendiente;
    final ancho = anchoDialogo(context, 400);
    // Las pestañas usan hasta 260px pero se achican si la ventana es baja
    // (el resto del diálogo ocupa unos 340px fijos).
    final alturaTabs =
        (MediaQuery.of(context).size.height - 400).clamp(150.0, 300.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: ancho,
        // Scroll de todo el diálogo: en una ventana baja el contenido se
        // desplaza en vez de desbordar por abajo.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogBanner(
              onCerrar: () => Navigator.pop(context),
              child: _AvatarConEditor(
                radio: 42,
                fotoPendiente: fotoPendiente,
                avatarUrl: _avatarUrlActual,
                inicial: usuario.nombreCompleto,
                cargando: _subiendoFoto,
                onEditar: () => _cambiarFoto(usuario),
              ),
            ),
            const SizedBox(height: 6),
            DialogRibbon(texto: usuario.nombreCompleto),
            if (fotoPendiente != null) ...[
              const SizedBox(height: 8),
              const Text('Foto guardada en el dispositivo · se subirá sola '
                  'cuando haya internet',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primario,
              unselectedLabelColor: Colors.black45,
              indicatorColor: AppColors.primario,
              tabs: const [
                Tab(icon: Icon(Icons.badge_outlined, size: 18), text: 'General'),
                Tab(icon: Icon(Icons.contact_page_outlined, size: 18), text: 'Personales'),
                Tab(icon: Icon(Icons.lock_outline, size: 18), text: 'Contraseña'),
              ],
            ),
            SizedBox(
              height: alturaTabs,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _tabDatosGenerales(usuario),
                  _tabPersonales(),
                  _tabPassword(),
                ],
              ),
            ),
            const Divider(height: 1),
            _barraAcciones(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _tabDatosGenerales(Usuario usuario) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nombreCtrl,
            maxLength: 120,
            decoration: decoracionCampoModerno('Nombre completo', Icons.person_outline),
          ),
          _CampoSoloLectura(
              label: 'Correo', valor: SupabaseService.currentUser?.email ?? '-'),
          _CampoSoloLectura(label: 'Rol', valor: Rol.etiqueta(usuario.rol)),
          if (_tabController.index == 0 && _error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tabPersonales() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: _cargandoDatos
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CamposDatosEmpleado(
                  ctrl: _datosCtrl,
                  // La fecha de ingreso la define el Gerente: acá solo se ve.
                  mostrarFechaIngreso: _datosCtrl.fechaIngreso != null,
                ),
                if (_tabController.index == 1 && _error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
    );
  }

  Widget _tabPassword() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nuevaCtrl,
            obscureText: true,
            maxLength: Validacion.passwordMax,
            decoration: decoracionCampoModerno('Nueva contraseña', Icons.lock_outline),
          ),
          TextField(
            controller: _confirmarCtrl,
            obscureText: true,
            maxLength: Validacion.passwordMax,
            decoration:
                decoracionCampoModerno('Confirmar contraseña', Icons.lock_outline),
          ),
          if (_tabController.index == 2 && _error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _barraAcciones() {
    final esPassword = _tabController.index == 2;
    final esPersonales = _tabController.index == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      // OverflowBar, no Row: "Guardar contraseña" es el texto más largo de
      // los tres botones posibles y, con "Cancelar" al lado, no siempre
      // entra en el ancho del diálogo en un teléfono angosto — un Row sin
      // Expanded se desbordaba (la franja de advertencia de Flutter tapando
      // los botones). OverflowBar los apila en vertical solo si hace falta.
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
            onPressed:
                _guardando
                ? null
                : (esPassword
                    ? _guardarPassword
                    : (esPersonales ? _guardarDatosPersonales : _guardarNombre)),
            child: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(esPassword
                    ? 'Guardar contraseña'
                    : (esPersonales ? 'Guardar datos' : 'Guardar')),
          ),
        ],
      ),
    );
  }
}

class _AvatarConEditor extends StatelessWidget {
  final double radio;
  final Uint8List? fotoPendiente;
  final String? avatarUrl;
  final String inicial;
  final bool cargando;
  final VoidCallback onEditar;
  const _AvatarConEditor({
    required this.radio,
    required this.fotoPendiente,
    required this.avatarUrl,
    required this.inicial,
    required this.cargando,
    required this.onEditar,
  });

  /// La foto que se está mostrando: la guardada sin internet tiene prioridad.
  ImageProvider? get _imagen => fotoPendiente != null
      ? MemoryImage(fotoPendiente!) as ImageProvider
      : (avatarUrl != null ? NetworkImage(avatarUrl!) : null);

  static const _tagFoto = 'foto_perfil';

  @override
  Widget build(BuildContext context) {
    final imagen = _imagen;
    final circulo = Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Hero(
        tag: _tagFoto,
        child: CircleAvatar(
          radius: radio,
          backgroundColor: AppColors.primario.withOpacity(0.1),
          backgroundImage: imagen,
          child: imagen == null
              ? Text(inicial.isNotEmpty ? inicial[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: radio * 0.7, color: AppColors.primario))
              : null,
        ),
      ),
    );

    return Stack(
      children: [
        // Con foto: tocarla la abre agrandada (como en una cuenta de
        // Google). Sin foto no hay nada que agrandar; para elegir una está
        // el botón de la cámara.
        if (imagen == null)
          circulo
        else
          Tooltip(
            message: 'Ver foto',
            child: MouseRegion(
              cursor: SystemMouseCursors.zoomIn,
              child: GestureDetector(
                onTap: () => mostrarFotoAmpliada(context,
                    imagen: imagen, titulo: inicial, tag: _tagFoto),
                child: circulo,
              ),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: InkWell(
            onTap: cargando ? null : onEditar,
            customBorder: const CircleBorder(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.secundario,
                shape: BoxShape.circle,
              ),
              child: cargando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _CampoSoloLectura extends StatelessWidget {
  final String label;
  final String valor;
  const _CampoSoloLectura({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(child: Text(valor, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
