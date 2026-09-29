import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../screens/perfil/perfil_dialog.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

/// Barra superior oscura: logo a la izquierda; a la derecha los accesos
/// rápidos (estado de sincronización, configuración)
/// y el bloque del usuario ("BIENVENIDO, nombre") con su menú.
class AppTopBar extends StatelessWidget {
  final void Function(String ruta) onNavegar;
  /// Si se pasa, se muestra el botón de menú (versión angosta/móvil).
  final VoidCallback? onMenu;
  const AppTopBar({super.key, required this.onNavegar, this.onMenu});

  void _abrirPerfil(BuildContext context) =>
      showDialog(context: context, builder: (_) => const PerfilDialog());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sync = context.watch<SyncService>();
    final usuario = auth.usuarioActual!;

    return Material(
      color: AppColors.negro,
      child: SizedBox(
        height: 60,
        child: LayoutBuilder(builder: (context, c) {
          final muyCompacto = c.maxWidth < 480;
          final estadoSync = !sync.online
              ? 'Sin conexión'
              : (sync.pendientes > 0
                  ? '${sync.pendientes} pendientes de sincronizar'
                  : 'En línea');

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (onMenu != null)
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    tooltip: 'Menú',
                    onPressed: onMenu,
                  ),
                Image.asset('assets/logo.png', height: 40),
                const Spacer(),
                _BotonTop(
                  icono: !sync.online
                      ? Icons.cloud_off
                      : (sync.pendientes > 0 ? Icons.sync : Icons.cloud_done),
                  color: (!sync.online || sync.pendientes > 0)
                      ? const Color(0xFFF0A030)
                      : const Color(0xFF3DA35D),
                  tooltip: estadoSync,
                  badge: sync.pendientes,
                ),
                _BotonTop(
                  icono: Icons.settings,
                  color: const Color(0xFFD9534F),
                  tooltip: 'Configuración',
                  onTap: () => _abrirPerfil(context),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  tooltip: 'Cuenta',
                  offset: const Offset(0, 48),
                  onSelected: (v) {
                    if (v == 'perfil') _abrirPerfil(context);
                    if (v == 'salir') auth.cerrarSesion();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'perfil',
                        child: ListTile(
                            dense: true,
                            leading: Icon(Icons.person_outline),
                            title: Text('Mi perfil'))),
                    PopupMenuItem(
                        value: 'salir',
                        child: ListTile(
                            dense: true,
                            leading: Icon(Icons.logout),
                            title: Text('Cerrar sesión'))),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primario,
                        backgroundImage: auth.fotoLocalPendiente != null
                            ? MemoryImage(auth.fotoLocalPendiente!)
                            : (usuario.avatarUrl != null
                                ? NetworkImage(usuario.avatarUrl!)
                                : null) as ImageProvider?,
                        child: auth.fotoLocalPendiente == null &&
                                usuario.avatarUrl == null
                            ? Text(
                                usuario.nombreCompleto.isNotEmpty
                                    ? usuario.nombreCompleto[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14))
                            : null,
                      ),
                      if (!muyCompacto) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('BIENVENIDO,',
                                  style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                      letterSpacing: 0.5)),
                              Text(usuario.nombreCompleto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Cuadrado de color de la barra superior (mismo estilo que los accesos
/// rápidos de la referencia).
class _BotonTop extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;
  const _BotonTop({
    required this.icono,
    required this.color,
    required this.tooltip,
    this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Badge(
          label: Text('$badge'),
          isLabelVisible: badge > 0,
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 40,
                height: 38,
                child: Icon(icono, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Inicio > Sección": migas de pan bajo la barra superior.
class AppBreadcrumb extends StatelessWidget {
  final String titulo;
  final bool esInicio;
  final VoidCallback onInicio;
  const AppBreadcrumb(
      {super.key,
      required this.titulo,
      required this.esInicio,
      required this.onInicio});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFEDEFF1),
      child: Row(
        children: [
          InkWell(
            onTap: onInicio,
            child: Row(
              children: [
                const Icon(Icons.home, size: 18, color: AppColors.primario),
                const SizedBox(width: 6),
                Text('Inicio',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primario,
                        fontWeight: esInicio ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
          ),
          if (!esInicio) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: Colors.black38),
            ),
            Flexible(
              child: Text(titulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila inferior oscura con la marca.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: double.infinity,
      color: AppColors.negro,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo.png', height: 26),
          const SizedBox(width: 10),
          const Text('© Salvietti Control',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
