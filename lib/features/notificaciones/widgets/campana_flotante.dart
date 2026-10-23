import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../models/aviso_campana.dart';
import '../services/campana_service.dart';

const _iconos = {
  'compras': Icons.shopping_cart_outlined,
  'solicitudes': Icons.mark_email_unread_outlined,
  'recetas': Icons.receipt_long_outlined,
  'respuesta': Icons.mark_chat_read_outlined,
};

/// Botón flotante con campana (abajo a la derecha, del lado contrario al
/// menú): muestra cuántas cosas hay pendientes y, al tocarlo, un panel con
/// cada tipo. Tocar una fila lleva a la pantalla donde se resuelve.
class CampanaFlotante extends StatelessWidget {
  final void Function(String ruta) onNavegar;
  const CampanaFlotante({super.key, required this.onNavegar});

  Future<void> _abrirPanel(BuildContext context) {
    final svc = context.read<CampanaService>();
    svc.cargar(); // por si algo cambió y Realtime no avisó
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar notificaciones',
      barrierColor: Colors.black12,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) => ChangeNotifierProvider.value(
        value: svc,
        child: _Panel(onElegir: (a) {
          Navigator.pop(ctx);
          svc.abrir(a);
          onNavegar(a.ruta);
        }, onNuevaSolicitud: () {
          Navigator.pop(ctx);
          onNavegar('solicitudes');
        }),
      ),
      transitionBuilder: (_, a, __, hijo) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(a),
          child: hijo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = context.watch<CampanaService>().total;
    return Tooltip(
      message: total == 0 ? 'Notificaciones' : '$total pendiente${total == 1 ? '' : 's'}',
      child: FloatingActionButton(
        heroTag: 'campana',
        backgroundColor: AppColors.primario,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => _abrirPanel(context),
        child: Badge(
          isLabelVisible: total > 0,
          label: Text(total > 99 ? '99+' : '$total'),
          backgroundColor: const Color(0xFFDC2626),
          offset: const Offset(10, -10),
          child: const Icon(Icons.notifications_rounded, size: 28),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final void Function(AvisoCampana) onElegir;
  final VoidCallback onNuevaSolicitud;
  const _Panel({required this.onElegir, required this.onNuevaSolicitud});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CampanaService>();
    final ancho = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          // Arriba del botón flotante.
          padding: const EdgeInsets.only(right: 16, bottom: 88, left: 16),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: ancho < 420 ? ancho - 32 : 380, maxHeight: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                    child: Row(children: [
                      const Icon(Icons.notifications_none_rounded, color: AppColors.primario),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Notificaciones',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primario)),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close, color: Colors.black45),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: svc.avisos.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No tenés nada pendiente.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: svc.avisos.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                            itemBuilder: (_, i) {
                              final a = svc.avisos[i];
                              return ListTile(
                                onTap: () => onElegir(a),
                                leading: Icon(_iconos[a.icono] ?? Icons.notifications_none,
                                    color: AppColors.primario),
                                title: Text(a.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(a.detalle, style: const TextStyle(fontSize: 12)),
                                trailing: CircleAvatar(
                                  radius: 13,
                                  backgroundColor: const Color(0xFFDC2626),
                                  child: Text(a.cantidad > 99 ? '99+' : '${a.cantidad}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              );
                            },
                          ),
                  ),
                  if (svc.puedeCrearSolicitud) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton.icon(
                        onPressed: onNuevaSolicitud,
                        icon: const Icon(Icons.add_comment_outlined),
                        label: const Text('Nueva solicitud o pregunta'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
