import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../models/compras_modelos.dart';
import '../repositories/compras_repository.dart';
import '../services/compras_service.dart';
import '../widgets/detalle_pedido_compra_dialog.dart';
import '../widgets/nuevo_pedido_compra_dialog.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Pedidos de compra: Almacén pide comprar (varios ítems) y el Gerente
/// aprueba o rechaza. Solo UI; las reglas viven en el service.
class ComprasScreen extends StatelessWidget {
  const ComprasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => ComprasService(SupabaseComprasRepository(), usuario)..iniciar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoNuevo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Nuevo pedido de compra',
    texto: 'Lo que hay que comprar. Lo aprueba el Gerente.',
  );
  final _pasoFiltros = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Filtrar por estado',
    texto: 'Pendientes, aprobados, rechazados o anulados.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'compras', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoNuevo, _pasoFiltros];

  Future<void> _nuevo(ComprasService svc) => showDialog<bool>(
        context: context,
        builder: (_) => NuevoPedidoCompraDialog(servicio: svc),
      );

  Future<void> _abrir(ComprasService svc, PedidoCompra p) => showDialog<bool>(
        context: context,
        builder: (_) => DetallePedidoCompraDialog(servicio: svc, pedido: p),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ComprasService>();
    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(child: Text('Tu rol no tiene acceso a los pedidos de compra.'));
    }
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(svc.error!, textAlign: TextAlign.center)),
          FilledButton(onPressed: svc.recargar, child: const Text('Reintentar')),
        ]),
      );
    }

    final lista = svc.visiblesFiltrados;
    // Lista perezosa: el encabezado es el ítem 0 (siempre montado, para el tour).
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 1 + (lista.isEmpty ? 1 : lista.length),
      itemBuilder: (context, i) {
        if (i == 0) {
          // Encabezado + buscador (texto, Desde/Hasta, PDF y Excel de lo filtrado).
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _encabezado(svc),
            BarraFiltros(
              filtro: svc.filtro,
              onCambio: svc.filtrar,
              reporte: svc.reporte,
              hint: 'Buscar por ítem, solicitante, motivo, N°…',
            ),
            const SizedBox(height: 12),
          ]);
        }
        if (lista.isEmpty) {
          if (svc.filtro.activo) return const SinResultados();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('No hay pedidos para mostrar.',
                    style: TextStyle(color: Colors.black54))),
          );
        }
        final p = lista[i - 1];
        return _TarjetaPedido(p: p, onTap: () => _abrir(svc, p));
      },
    );
  }

  Widget _encabezado(ComprasService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(
            child: Text('Pedidos de compra',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          BotonAyuda(idTour: 'compras', pasos: _pasosAyuda),
        ]),
        if (svc.puedeCrear) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _pasoNuevo.envolver(FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
              onPressed: () => _nuevo(svc),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Nuevo pedido de compra'),
            )),
          ),
        ],
        const SizedBox(height: 12),
        _pasoFiltros.envolver(Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: svc.filtroEstado == null,
              onSelected: (_) => svc.filtrarEstado(null),
            ),
            for (final e in EstadoCompra.values)
              ChoiceChip(
                label: Text(e == EstadoCompra.pendiente && svc.pendientes > 0
                    ? '${e.etiqueta} (${svc.pendientes})'
                    : e.etiqueta),
                selected: svc.filtroEstado == e,
                onSelected: (_) => svc.filtrarEstado(e),
              ),
          ],
        )),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  final PedidoCompra p;
  final VoidCallback onTap;
  const _TarjetaPedido({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = colorEstadoCompra(p.estado);
    final resumen = p.lineas.take(3).map((l) => l.detalle).join(', ') +
        (p.lineas.length > 3 ? ' y ${p.lineas.length - 3} más' : '');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(Icons.shopping_cart_outlined, color: color),
        ),
        title: Text('#${p.id} · ${p.lineas.length} ítem${p.lineas.length == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$resumen\n${p.solicitanteNombre ?? '—'} · ${fmtFechaHora(p.fecha)}',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: Text(p.estado.etiqueta,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
