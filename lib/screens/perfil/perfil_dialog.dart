import 'dart:async';
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
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';

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
/// (al estilo de una cuenta de Google), más un cambio de contraseña.
/// El rol y el estado activo NUNCA se pueden tocar desde acá — eso sigue
/// siendo exclusivo de Gerente en la pantalla de Usuarios.
class PerfilDialog extends StatefulWidget {
  const PerfilDialog({super.key});

  @override
  State<PerfilDialog> createState() => _PerfilDialogState();
}

class _PerfilDialogState extends State<PerfilDialog> {
  late final TextEditingController _nombreCtrl;
  bool _subiendoFoto = false;
  bool _guardando = false;
  String? _error;
  String? _avatarUrlActual;

  @override
  void initState() {
    super.initState();
    final usuario = context.read<AuthService>().usuarioActual!;
    _nombreCtrl = TextEditingController(text: usuario.nombreCompleto);
    _avatarUrlActual = usuario.avatarUrl;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
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

  Future<void> _abrirCambiarPassword() async {
    await showDialog(
      context: context,
      builder: (_) => const _CambiarPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final usuario = auth.usuarioActual!;
    final fotoPendiente = auth.fotoLocalPendiente;
    return AlertDialog(
      title: const Text('Mi perfil'),
      content: SizedBox(
        width: anchoDialogo(context, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primario.withOpacity(0.1),
                    backgroundImage: fotoPendiente != null
                        ? MemoryImage(fotoPendiente)
                        : (_avatarUrlActual != null
                            ? NetworkImage(_avatarUrlActual!)
                            : null) as ImageProvider?,
                    child: fotoPendiente == null && _avatarUrlActual == null
                        ? Text(
                            usuario.nombreCompleto.isNotEmpty
                                ? usuario.nombreCompleto[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 32, color: AppColors.primario),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _subiendoFoto ? null : () => _cambiarFoto(usuario),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primario,
                          shape: BoxShape.circle,
                        ),
                        child: _subiendoFoto
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (fotoPendiente != null) ...[
              const SizedBox(height: 8),
              const Text('Foto guardada en el dispositivo · se subirá sola '
                  'cuando haya internet',
                  style: TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _nombreCtrl,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
            ),
            _CampoSoloLectura(
                label: 'Correo', valor: SupabaseService.currentUser?.email ?? '-'),
            _CampoSoloLectura(label: 'Rol', valor: Rol.etiqueta(usuario.rol)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _abrirCambiarPassword,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Cambiar contraseña'),
              ),
            ),
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
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardarNombre,
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

class _CampoSoloLectura extends StatelessWidget {
  final String label;
  final String valor;
  const _CampoSoloLectura({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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

class _CambiarPasswordDialog extends StatefulWidget {
  const _CambiarPasswordDialog();

  @override
  State<_CambiarPasswordDialog> createState() =>
      _CambiarPasswordDialogState();
}

class _CambiarPasswordDialogState extends State<_CambiarPasswordDialog> {
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
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
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SizedBox(
        width: anchoDialogo(context, 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nuevaCtrl,
              obscureText: true,
              maxLength: Validacion.passwordMax,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
            ),
            TextField(
              controller: _confirmarCtrl,
              obscureText: true,
              maxLength: Validacion.passwordMax,
              decoration:
                  const InputDecoration(labelText: 'Confirmar contraseña'),
            ),
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
            child: const Text('Cancelar')),
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
