import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/entregas_modelos.dart';
import '../repositories/entregas_repository.dart';
import '../services/entregas_service.dart';
import '../widgets/conformidad_dialog.dart';
import '../widgets/devolucion_dialog.dart';
import '../widgets/motivo_dialog.dart';
import '../widgets/pedido_form_dialog.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Bandeja de pedidos internos: por entregar, por confirmar, con
/// observaciones y cerrados. Solo UI; las reglas viven en el service.
class EntregasScreen extends StatelessWidget {
  const EntregasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          EntregasService(SupabaseEntregasRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<EntregasService>().recargar(),
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
    texto: 'Pedidos por estado; el número es cuántos hay.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'entregas', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoBandejas];

  Future<void> _nuevoPedido(BuildContext context, EntregasService svc) => showDialog<bool>(
        context: context,
        builder: (_) => PedidoFormDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EntregasService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Entregas.'),
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
                    child: Text('Entregas',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  BotonAyuda(idTour: 'entregas', pasos: _pasosAyuda),
                ],
              ),
              if (svc.puedeCrearPedido) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: () => _nuevoPedido(context, svc),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo pedido'),
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
              runSpacing: 6,
              children: [
                for (final b in BandejaPedidos.values)
                  ChoiceChip(
                    label: Text('${b.etiqueta} (${svc.cantidadEn(b)})'),
                    selected: svc.bandeja == b,
                    selectedColor: AppColors.primario,
                    labelStyle: TextStyle(
                        color: svc.bandeja == b ? Colors.white : Colors.black87),
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
            hint: 'Buscar por área, almacén, solicitante, N°…',
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? (svc.filtro.activo
                  ? const SinResultados()
                  : const Center(
                      child: Text('No hay pedidos en esta bandeja.',
                          style: TextStyle(color: Colors.black54))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _TarjetaPedido(svc: svc, pedido: items[i]),
                ),
        ),
      ],
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  final EntregasService svc;
  final Pedido pedido;
  const _TarjetaPedido({required this.svc, required this.pedido});

  Color _colorEstado(EstadoPedido e) {
    switch (e) {
      case EstadoPedido.pendiente:
        return const Color(0xFFD97706);
      case EstadoPedido.entregado:
        return AppColors.secundario;
      case EstadoPedido.observado:
        return const Color(0xFFDC2626);
      case EstadoPedido.cerrado:
        return const Color(0xFF16A34A);
      case EstadoPedido.anulado:
        return Colors.black45;
    }
  }

  Future<void> _entregar(BuildContext context) async {
    final error = await svc.entregar(pedido);
    if (!context.mounted) return;
    error == null ? mostrarExito(context, 'Pedido entregado.') : mostrarError(context, error);
  }

  Future<void> _confirmar(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => ConformidadDialog(servicio: svc, pedido: pedido),
      );

  Future<void> _resolver(BuildContext context) => pedirMotivo(
        context,
        titulo: 'Resolver observación',
        etiqueta: 'Cómo se resolvió',
        onConfirmar: (t) => svc.resolver(pedido, t),
      );

  Future<void> _anular(BuildContext context) => pedirMotivo(
        context,
        titulo: 'Anular pedido',
        etiqueta: 'Motivo',
        onConfirmar: (t) => svc.anular(pedido, t),
      );

  Future<void> _devolver(BuildContext context, LineaPedido l) => showDialog<bool>(
        context: context,
        builder: (_) => DevolucionDialog(servicio: svc, pedido: pedido, linea: l),
      );

  @override
  Widget build(BuildContext context) {
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
                  child: Text('Pedido #${pedido.id} · ${AreaPedido.etiqueta(pedido.areaDestino)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _colorEstado(pedido.estado).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(pedido.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _colorEstado(pedido.estado))),
                ),
              ],
            ),
            Text(
              'Pedido por ${pedido.solicitanteNombre ?? '—'} · ${fmtFecha(pedido.fecha)}'
              '${pedido.motivo == null ? '' : ' · ${pedido.motivo}'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            for (final l in pedido.lineas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(l.detalle)),
                    Text(
                      pedido.estado == EstadoPedido.pendiente
                          ? '${fmtNum(l.cantidadPedida)} ${l.unidad}'
                          : '${fmtNum(l.cantidadEntregada ?? l.cantidadPedida)} ${l.unidad}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (l.cantidadDevuelta > 0) ...[
                      const SizedBox(width: 6),
                      Text('(devuelto ${fmtNum(l.cantidadDevuelta)})',
                          style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                    if (l.observacion != null) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: Color(0xFFD97706)),
                    ],
                    if (svc.puedeDevolver(pedido, l))
                      IconButton(
                        tooltip: 'Registrar devolución',
                        icon: const Icon(Icons.keyboard_return, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _devolver(context, l),
                      ),
                  ],
                ),
              ),
            if (pedido.resolucion != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Resolución: ${pedido.resolucion}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            if (svc.puedeEntregar(pedido) ||
                svc.puedeConfirmar(pedido) ||
                svc.puedeResolver(pedido) ||
                svc.puedeAnular(pedido)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (svc.puedeEntregar(pedido))
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                        onPressed: () => _entregar(context),
                        child: const Text('Entregar')),
                  if (svc.puedeConfirmar(pedido))
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                        onPressed: () => _confirmar(context),
                        child: const Text('Confirmar recepción')),
                  if (svc.puedeResolver(pedido))
                    OutlinedButton(
                        onPressed: () => _resolver(context), child: const Text('Resolver')),
                  if (svc.puedeAnular(pedido))
                    TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                        onPressed: () => _anular(context),
                        child: const Text('Anular')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
