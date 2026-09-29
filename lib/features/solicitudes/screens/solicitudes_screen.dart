import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/solicitud.dart';
import '../repositories/solicitudes_repository.dart';
import '../services/solicitud_pdf_service.dart';
import '../services/solicitudes_service.dart';
import '../widgets/resolver_solicitud_dialog.dart';
import '../widgets/solicitud_form_dialog.dart';

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
      child: const _Vista(),
    );
  }
}

class _Vista extends StatelessWidget {
  const _Vista();

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

    final items = svc.visibles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Solicitudes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              if (svc.puedeCrear)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: () => _nueva(context, svc),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva solicitud'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final b in BandejaSolicitudes.values)
                if (b != BandejaSolicitudes.porAprobar || svc.puedeAprobar)
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
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No hay solicitudes para mostrar.',
                      style: TextStyle(color: Colors.black54)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _Tarjeta(svc: svc, s: items[i]),
                ),
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final SolicitudesService svc;
  final Solicitud s;
  const _Tarjeta({required this.svc, required this.s});

  Color _colorEstado() {
    switch (s.estado) {
      case EstadoSolicitud.pendiente:
        return const Color(0xFFD97706);
      case EstadoSolicitud.aprobada:
        return const Color(0xFF16A34A);
      case EstadoSolicitud.rechazada:
        return const Color(0xFFDC2626);
    }
  }

  Future<void> _resolver(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => ResolverSolicitudDialog(servicio: svc, solicitud: s),
      );

  Future<void> _imprimir(BuildContext context) async {
    try {
      final bytes = await SolicitudPdfService.pdf(s);
      final mensaje = await SolicitudPdfService.guardar(bytes, s);
      if (context.mounted) mostrarExito(context, mensaje);
    } catch (_) {
      if (context.mounted) mostrarError(context, 'No se pudo generar el PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeResolver = svc.puedeAprobar && s.estado == EstadoSolicitud.pendiente;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.asunto,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _colorEstado().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(s.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: _colorEstado())),
                ),
              ],
            ),
            Text(
              '${TipoSolicitud.etiqueta(s.tipo)} · ${s.solicitanteNombre ?? '—'} · ${fmtFechaHora(s.fecha)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (s.itemDetalle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ítem: ${s.itemDetalle}'
                  '${s.cantidadSugerida == null ? '' : ' · ${fmtNum(s.cantidadSugerida)} ${s.itemUnidad ?? ''}'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (s.detalle != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(s.detalle!),
              ),
            if (s.respuesta != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Respuesta de ${s.resueltaPorNombre ?? 'Gerencia'}: ${s.respuesta}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _imprimir(context),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Constancia PDF'),
                ),
                if (puedeResolver)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: () => _resolver(context),
                    child: const Text('Resolver'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
