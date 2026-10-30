import 'package:flutter/material.dart';
import '../../../shared/opciones_deslizables.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../repositories/solicitudes_repository.dart';
import '../services/solicitudes_service.dart';
import '../widgets/lista_recetas.dart';
import '../widgets/conversacion_solicitud.dart';
import '../widgets/solicitud_form_dialog.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Solicitudes a Gerencia: cualquier área pide algo (suministro,
/// autorización, cambio de receta...) y Gerencia lo aprueba o rechaza desde
/// una sola bandeja. Solo UI; las reglas viven en el service.
/// Una pestaña más al lado de "Mis solicitudes" (Pedidos de las áreas, Pedidos
/// de compra): la arma quien abre Solicitudes, así este módulo no depende de
/// las pantallas de los otros.
class PestanaExtra {
  final String id;
  final String etiqueta;
  final IconData icono;
  final Widget Function() construir;
  const PestanaExtra(
      {required this.id, required this.etiqueta, required this.icono, required this.construir});

  @override
  bool operator ==(Object other) => other is PestanaExtra && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class SolicitudesScreen extends StatelessWidget {
  final List<PestanaExtra> extras;

  /// id de la pestaña extra con la que abre (ej. desde la campana).
  final String? inicial;
  const SolicitudesScreen({super.key, this.extras = const [], this.inicial});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          SolicitudesService(SupabaseSolicitudesRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<SolicitudesService>().recargar(),
        child: _Vista(extras: extras, inicial: inicial),
      ),
    );
  }
}

class _Vista extends StatefulWidget {
  final List<PestanaExtra> extras;
  final String? inicial;
  const _Vista({required this.extras, this.inicial});

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoBandejas = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Bandejas',
    texto: 'Pedidos a Gerencia, por estado.',
  );

  /// Pestaña extra elegida; null = una bandeja de solicitudes.
  PestanaExtra? _extra;

  @override
  void initState() {
    super.initState();
    _extra = widget.extras.where((e) => e.id == widget.inicial).firstOrNull;
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
    if (!svc.puedeVer && widget.extras.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Solicitudes.'),
        ),
      );
    }
    // Sin acceso a las solicitudes pero sí a los pedidos: abre en esos.
    final extra = svc.puedeVer ? _extra : (_extra ?? widget.extras.first);
    if (svc.error != null && extra == null) {
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
              if (svc.puedeCrear && extra == null) ...[
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
            OpcionesDeslizables<Object>(
              opciones: [if (svc.puedeVer) ...svc.bandejas, ...widget.extras],
              seleccionada: extra ?? svc.bandeja,
              etiqueta: (o) => o is PestanaExtra
                  ? o.etiqueta
                  : o == BandejaSolicitudes.porAprobar && svc.pendientesDeAprobar > 0
                      ? '${(o as BandejaSolicitudes).etiqueta} (${svc.pendientesDeAprobar})'
                      : (o as BandejaSolicitudes).etiqueta,
              icono: (o) => o is PestanaExtra ? o.icono : null,
              onElegir: (o) {
                setState(() => _extra = o is PestanaExtra ? o : null);
                if (o is BandejaSolicitudes) svc.elegirBandeja(o);
              },
            ),
          ),
        ),
        // Pedidos de las áreas / de compra: su propia pantalla, sin título.
        if (extra != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: KeyedSubtree(key: ValueKey(extra.id), child: extra.construir()),
            ),
          )
        else ...[
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
        if (svc.bandeja == BandejaSolicitudes.recetas)
          Expanded(child: ListaRecetas(recetas: svc.recetasFiltradas, filtrando: svc.filtro.activo))
        else
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
      ],
    );
  }
}
