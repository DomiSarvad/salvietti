import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../services/preferencias_service.dart';
import '../../services/sync_service.dart';
import '../../shared/ayuda/tour_ayuda.dart';
import '../../utils/notificaciones.dart';

/// Configuración general de la app — cosas del dispositivo/la sesión, no
/// del usuario (eso vive en "Mi perfil"): sincronización y apariencia.
/// El botón del engranaje en la barra superior abre esta pantalla.
class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key});

  Future<void> _sincronizarAhora(BuildContext context, SyncService sync) async {
    final resultado = await sync.sincronizarTodo();
    if (context.mounted) mostrarInfo(context, resultado);
  }

  Future<void> _reiniciarTours(BuildContext context) async {
    await TourAyuda.reiniciarTodos();
    if (context.mounted) {
      mostrarExito(context, 'Los recorridos con globitos van a volver a aparecer solos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final prefs = context.watch<PreferenciasService>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Configuración', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        _Seccion(
          icono: Icons.sync,
          titulo: 'Sincronización',
          children: [
            Row(
              children: [
                Icon(
                  !sync.online
                      ? Icons.cloud_off
                      : (sync.pendientes > 0 ? Icons.sync_problem : Icons.cloud_done),
                  color: (!sync.online || sync.pendientes > 0)
                      ? const Color(0xFFD97706)
                      : const Color(0xFF16A34A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !sync.online
                        ? 'Sin conexión.'
                        : (sync.pendientes > 0
                            ? '${sync.pendientes} movimiento${sync.pendientes == 1 ? '' : 's'} sin subir todavía.'
                            : 'Todo sincronizado.'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: sync.sincronizando || sync.pendientes == 0 || !sync.online
                  ? null
                  : () => _sincronizarAhora(context, sync),
              icon: sync.sincronizando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(sync.sincronizando ? 'Sincronizando…' : 'Sincronizar ahora'),
            ),
            const SizedBox(height: 2),
            const Text(
                'Lo pendiente se sube solo al recuperar conexión; este botón lo fuerza ahora.',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 16),
        _Seccion(
          icono: Icons.text_fields,
          titulo: 'Tamaño de letra',
          children: [
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 0.9, label: Text('Chico')),
                ButtonSegment(value: 1.0, label: Text('Normal')),
                ButtonSegment(value: 1.15, label: Text('Grande')),
              ],
              selected: {prefs.escalaTexto},
              onSelectionChanged: (v) => prefs.cambiarEscalaTexto(v.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) ? Colors.white : AppColors.primario),
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) ? AppColors.primario : null),
              ),
            ),
            const SizedBox(height: 2),
            const Text('Se aplica a toda la app al toque.',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 16),
        _Seccion(
          icono: Icons.help_outline,
          titulo: 'Ayuda',
          children: [
            OutlinedButton.icon(
              onPressed: () => _reiniciarTours(context),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Reiniciar recorridos guiados'),
            ),
            const SizedBox(height: 2),
            const Text(
                'Hace que los recorridos con globitos ("?") vuelvan a mostrarse solos la '
                'próxima vez que entres a cada pantalla, como si fuera la primera vez.',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final List<Widget> children;
  const _Seccion({required this.icono, required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icono, size: 18, color: AppColors.primario),
            const SizedBox(width: 8),
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
