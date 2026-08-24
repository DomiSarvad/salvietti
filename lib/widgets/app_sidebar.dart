import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
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
      _Item('inventario', 'Inventario', Icons.inventory_2_outlined, true),
      _Item('produccion', 'Producción', Icons.factory_outlined,
          !usuario.soloLectura),
      _Item('historial', 'Historial / Bitácora', Icons.history,
          usuario.esAlmacen || usuario.esGerente),
      _Item('usuarios', 'Usuarios', Icons.people_outline,
          usuario.puedeCrearUsuarios),
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
            child: const Row(
              children: [
                Icon(Icons.local_drink, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Expanded(
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
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person, size: 18)),
            title: Text(usuario.nombreCompleto,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
            subtitle: Text(Rol.etiqueta(usuario.rol),
                style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.logout, size: 18),
              tooltip: 'Cerrar sesión',
              onPressed: () => auth.cerrarSesion(),
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
