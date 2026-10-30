import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../screens/perfil/perfil_dialog.dart';
import '../shared/pagina_o_dialogo.dart';
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

  /// En el celular, página a pantalla completa; en la compu, una ventana.
  void _abrirPerfil(BuildContext context) => abrirPaginaODialogo(context,
      titulo: 'Mi perfil', builder: (pagina) => PerfilDialog(comoPantalla: pagina));

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
                // Sincronización: su color ES el estado (verde al día, ámbar
                // subiendo, gris sin internet), y gira mientras sube.
                _BotonTop(
                  icono: !sync.online
                      ? Icons.cloud_off_rounded
                      : (sync.pendientes > 0 ? Icons.sync_rounded : Icons.cloud_done_rounded),
                  gradiente: !sync.online
                      ? const [Color(0xFF9AA4AE), Color(0xFF5E6873)]
                      : sync.pendientes > 0
                          ? const [Color(0xFFFFC857), Color(0xFFE08A12)]
                          : const [Color(0xFF4CD486), Color(0xFF1E9B55)],
                  girar: sync.online && sync.pendientes > 0,
                  tooltip: estadoSync,
                  badge: sync.pendientes,
                ),
                // Configuración no informa nada: vidrio, para no competir.
                _BotonTop(
                  icono: Icons.settings_rounded,
                  tooltip: 'Configuración',
                  onTap: () => onNavegar('configuracion'),
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
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF2D27A), AppColors.secundario],
                          ),
                        ),
                        child: CircleAvatar(
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
                      )),
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

/// Botón de la barra superior. Con [gradiente]: relleno degradado y un brillo
/// suave de su color (el estado de la sincronización se ve de lejos). Sin
/// gradiente: "vidrio" translúcido, para acciones que no informan un estado
/// (Configuración). Al pasar el mouse se levanta apenas; [girar] lo hace
/// rotar (mientras se sube algo pendiente).
class _BotonTop extends StatefulWidget {
  final IconData icono;
  final List<Color>? gradiente;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;
  final bool girar;
  const _BotonTop({
    required this.icono,
    required this.tooltip,
    this.gradiente,
    this.onTap,
    this.badge = 0,
    this.girar = false,
  });

  @override
  State<_BotonTop> createState() => _BotonTopState();
}

class _BotonTopState extends State<_BotonTop> with SingleTickerProviderStateMixin {
  late final _giro = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  bool _encima = false;

  @override
  void initState() {
    super.initState();
    if (widget.girar) _giro.repeat();
  }

  @override
  void didUpdateWidget(_BotonTop viejo) {
    super.didUpdateWidget(viejo);
    if (widget.girar && !_giro.isAnimating) _giro.repeat();
    if (!widget.girar && _giro.isAnimating) {
      _giro.stop();
      _giro.value = 0;
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gradiente;
    final radio = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: widget.tooltip,
        child: Badge(
          label: Text('${widget.badge}'),
          isLabelVisible: widget.badge > 0,
          child: MouseRegion(
            onEnter: (_) => setState(() => _encima = true),
            onExit: (_) => setState(() => _encima = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, _encima ? -1.5 : 0, 0),
              decoration: BoxDecoration(
                borderRadius: radio,
                gradient: g == null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
                color: g == null ? Colors.white.withValues(alpha: _encima ? 0.16 : 0.09) : null,
                // Borde claro arriba: da el relieve de "botón" en vez de un plano.
                border: Border.all(color: Colors.white.withValues(alpha: g == null ? 0.18 : 0.28)),
                boxShadow: g == null
                    ? null
                    : [
                        BoxShadow(
                          color: g.last.withValues(alpha: _encima ? 0.6 : 0.4),
                          blurRadius: _encima ? 14 : 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: radio,
                  child: SizedBox(
                    width: 40,
                    height: 38,
                    child: RotationTransition(
                      turns: _giro,
                      child: Icon(widget.icono, size: 21, color: Colors.white),
                    ),
                  ),
                ),
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
