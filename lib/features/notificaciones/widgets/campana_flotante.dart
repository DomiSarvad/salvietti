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
    // Como los botones de la barra superior: degradado con borde claro y
    // brillo de su color; dorado cuando hay algo pendiente.
    final colores = total > 0
        ? const [Color(0xFFE2B85A), AppColors.secundario]
        : const [Color(0xFF2E8B57), AppColors.primario];
    return Tooltip(
      message: total == 0 ? 'Notificaciones' : '$total pendiente${total == 1 ? '' : 's'}',
      child: Badge(
        isLabelVisible: total > 0,
        label: Text(total > 99 ? '99+' : '$total'),
        backgroundColor: const Color(0xFFDC2626),
        offset: const Offset(-2, 2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colores),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(color: colores.last.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _abrirPanel(context),
              child: Icon(
                  total > 0 ? Icons.notifications_active_rounded : Icons.notifications_rounded,
                  size: 27,
                  color: Colors.white),
            ),
          ),
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
                  if (svc.puedeCrearSolicitud || svc.puedeVerSolicitudes) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton.icon(
                        onPressed: onNuevaSolicitud,
                        icon: Icon(svc.puedeCrearSolicitud
                            ? Icons.add_comment_outlined
                            : Icons.mark_email_read_outlined),
                        label: Text(svc.puedeCrearSolicitud
                            ? 'Nueva solicitud o pregunta'
                            : 'Ver solicitudes'),
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
