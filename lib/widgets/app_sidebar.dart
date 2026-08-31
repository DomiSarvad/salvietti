import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../screens/perfil/perfil_dialog.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class AppSidebar extends StatelessWidget {
  final String rutaActual;
  final void Function(String ruta) onNavegar;
  const AppSidebar(
      {super.key, required this.rutaActual, required this.onNavegar});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sync = context.watch<SyncService>();
    final usuario = auth.usuarioActual!;

    final items = <_Item>[
      _Item('dashboard', 'Dashboard', Icons.dashboard_outlined, true),
      _Item('inventario', 'Inventario', Icons.inventory_2_outlined,
          usuario.puedeVerInventario),
      _Item('produccion', 'Producción', Icons.factory_outlined,
          usuario.puedeVerProduccion),
      _Item('estadisticas', 'Estadísticas', Icons.bar_chart_outlined,
          usuario.puedeVerEstadisticas),
      _Item('reportes', 'Reportes', Icons.picture_as_pdf_outlined,
          usuario.puedeVerReportes),
      _Item('historial', 'Historial / Bitácora', Icons.history,
          usuario.esAlmacen || usuario.esGerente),
      _Item('usuarios', 'Usuarios', Icons.people_outline,
          usuario.puedeVerUsuarios),
    ];

    return Container(
      width: 260,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.primario,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.jpg', width: 34, height: 34),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Salvietti Control',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(sync.online ? Icons.cloud_done : Icons.cloud_off,
                    size: 16,
                    color: sync.online ? Colors.green : Colors.orange),
                const SizedBox(width: 6),
                Text(sync.online ? 'En línea' : 'Sin conexión',
                    style: const TextStyle(fontSize: 12)),
                const Spacer(),
                if (sync.pendientes > 0)
                  Chip(
                    label: Text('${sync.pendientes} pend.'),
                    backgroundColor: Colors.orange.shade100,
                    labelStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable: en ventanas bajas con muchos ítems de menú visibles,
          // esta lista se desplaza en vez de desbordar toda la columna.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in items.where((i) => i.visible))
                  ListTile(
                    leading: Icon(item.icono,
                        color: rutaActual == item.ruta
                            ? AppColors.primario
                            : Colors.black54),
                    title: Text(item.titulo,
                        style: TextStyle(
                            color: rutaActual == item.ruta
                                ? AppColors.primario
                                : Colors.black87,
                            fontWeight: rutaActual == item.ruta
                                ? FontWeight.bold
                                : FontWeight.normal)),
                    selected: rutaActual == item.ruta,
                    selectedTileColor: AppColors.primario.withOpacity(0.08),
                    onTap: () => onNavegar(item.ruta),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Fila armada a mano (no ListTile) para no depender de su alto
          // mínimo fijo, que con avatar + 2 líneas de texto + botón podía
          // desbordar unos pixeles según el tamaño de fuente del sistema.
          InkWell(
            onTap: () => showDialog(
                context: context, builder: (_) => const PerfilDialog()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: auth.fotoLocalPendiente != null
                        ? MemoryImage(auth.fotoLocalPendiente!)
                        : (usuario.avatarUrl != null
                            ? NetworkImage(usuario.avatarUrl!)
                            : null) as ImageProvider?,
                    child: auth.fotoLocalPendiente == null &&
                            usuario.avatarUrl == null
                        ? Text(usuario.nombreCompleto.isNotEmpty
                            ? usuario.nombreCompleto[0].toUpperCase()
                            : '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(usuario.nombreCompleto,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(Rol.etiqueta(usuario.rol),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, size: 18),
                    tooltip: 'Cerrar sesión',
                    onPressed: () => auth.cerrarSesion(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String ruta;
  final String titulo;
  final IconData icono;
  final bool visible;
  _Item(this.ruta, this.titulo, this.icono, this.visible);
}
