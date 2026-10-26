import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../repositories/solicitudes_repository.dart';
import '../services/solicitudes_service.dart';
import '../widgets/conversacion_solicitud.dart';
import '../widgets/solicitud_form_dialog.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Solicitudes a Gerencia: cualquier área pide algo (suministro,
/// autorización, cambio de receta...) y Gerencia lo aprueba o rechaza desde
/// una sola bandeja. Solo UI; las reglas viven en el service.
class SolicitudesScreen extends StatelessWidget {
  const SolicitudesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          SolicitudesService(SupabaseSolicitudesRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<SolicitudesService>().recargar(),
        child: const _Vista(),
      ),
    );
  }
}

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoBandejas = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Bandejas',
    texto: 'Pedidos a Gerencia, por estado.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context,
            idTour: 'solicitudes', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoBandejas];

  Future<void> _nueva(BuildContext context, SolicitudesService svc) => showDialog<bool>(
        context: context,
        builder: (_) => SolicitudFormDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SolicitudesService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Solicitudes.'),
        ),
      );
    }
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
        ]),
      );
    }

    final items = svc.visiblesFiltrados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Solicitudes',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  BotonAyuda(idTour: 'solicitudes', pasos: _pasosAyuda),
                ],
              ),
              if (svc.puedeCrear) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: () => _nueva(context, svc),
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva solicitud'),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _pasoBandejas.envolver(
            Wrap(
              spacing: 8,
              children: [
                for (final b in svc.bandejas)
                  ChoiceChip(
                      label: Text(b == BandejaSolicitudes.porAprobar && svc.pendientesDeAprobar > 0
                          ? '${b.etiqueta} (${svc.pendientesDeAprobar})'
                          : b.etiqueta),
                      selected: svc.bandeja == b,
                      selectedColor: AppColors.primario,
                      labelStyle:
                          TextStyle(color: svc.bandeja == b ? Colors.white : Colors.black87),
                      onSelected: (_) => svc.elegirBandeja(b),
                    ),
              ],
            ),
          ),
        ),
        // Buscador: texto, Desde/Hasta, y PDF/Excel de lo filtrado (dentro de la
        // bandeja elegida).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: BarraFiltros(
            filtro: svc.filtro,
            onCambio: svc.filtrar,
            reporte: svc.reporte,
            hint: 'Buscar por asunto, ítem, solicitante, tipo…',
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? (svc.filtro.activo
                  ? const SinResultados()
                  : const Center(
                      child: Text('No hay solicitudes para mostrar.',
                          style: TextStyle(color: Colors.black54))))
              // Como una bandeja de mensajes: una fila por conversación;
              // tocarla abre el chat con el pedido y la respuesta.
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72, color: Color(0xFFE8ECEF)),
                      itemBuilder: (context, i) => FilaConversacion(
                        s: items[i],
                        mia: svc.esMia(items[i]),
                        onTap: () => ConversacionSolicitud.abrir(context, svc, items[i]),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
