import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/compras_modelos.dart';
import '../services/compras_service.dart';

Color colorEstadoCompra(EstadoCompra e) {
  switch (e) {
    case EstadoCompra.pendiente:
      return const Color(0xFFD97706);
    case EstadoCompra.aprobado:
      return const Color(0xFF16A34A);
    case EstadoCompra.rechazado:
      return const Color(0xFFDC2626);
    case EstadoCompra.anulado:
      return Colors.black45;
  }
}

/// Detalle de un pedido de compra. El Gerente lo aprueba o rechaza (con
/// respuesta, obligatoria si rechaza); quien lo hizo lo puede anular.
class DetallePedidoCompraDialog extends StatefulWidget {
  final ComprasService servicio;
  final PedidoCompra pedido;
  const DetallePedidoCompraDialog({super.key, required this.servicio, required this.pedido});

  @override
  State<DetallePedidoCompraDialog> createState() => _DetallePedidoCompraDialogState();
}

class _DetallePedidoCompraDialogState extends State<DetallePedidoCompraDialog> {
  final _respuesta = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _respuesta.dispose();
    super.dispose();
  }

  Future<void> _hacer(Future<String?> Function() accion, String ok) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await accion();
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, ok);
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final svc = widget.servicio;
    final resolver = svc.puedeAprobar && p.estado == EstadoCompra.pendiente;
    final ancho = MediaQuery.sizeOf(context).width;

    return AlertDialog(
      title: Text('Pedido de compra #${p.id}'),
      content: SizedBox(
        width: ancho < 560 ? ancho : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Chip(
                  label: Text(p.estado.etiqueta,
                      style: TextStyle(color: colorEstadoCompra(p.estado), fontWeight: FontWeight.w700)),
                  backgroundColor: colorEstadoCompra(p.estado).withValues(alpha: 0.1),
                  side: BorderSide.none,
                ),
                Text('${p.solicitanteNombre ?? '—'} · ${fmtFechaHora(p.fecha)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
              if (p.motivo != null) ...[
                const SizedBox(height: 8),
                Text(p.motivo!),
              ],
              const SizedBox(height: 12),
              const Text('Ítems', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final l in p.lineas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${l.codigo} · ${l.detalle}'),
                            if (l.nota != null)
                              Text(l.nota!,
                                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${fmtNum(l.cantidad)} ${l.unidad}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (p.estado != EstadoCompra.pendiente && p.estado != EstadoCompra.anulado) ...[
                const Divider(height: 24),
                Text('${p.estado.etiqueta} por ${p.resueltoPorNombre ?? '—'}'
                    '${p.resueltoEn == null ? '' : ' · ${fmtFechaHora(p.resueltoEn)}'}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (p.respuesta != null) ...[
                  const SizedBox(height: 4),
                  Text(p.respuesta!),
                ],
              ],
              if (resolver) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _respuesta,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Respuesta',
                    counterText: '',
                    helperText: 'Obligatoria si vas a rechazar.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (svc.puedeAnular(p))
          TextButton(
            onPressed: _guardando
                ? null
                : () => _hacer(() => svc.anular(p), 'Pedido anulado.'),
            child: const Text('Anular pedido'),
          ),
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cerrar')),
        if (resolver) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: _guardando
                ? null
                : () => _hacer(() => svc.rechazar(p, _respuesta.text), 'Pedido rechazado.'),
            child: const Text('Rechazar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
            onPressed: _guardando
                ? null
                : () => _hacer(() => svc.aprobar(p, respuesta: _respuesta.text), 'Pedido aprobado.'),
            child: const Text('Aprobar'),
          ),
        ],
      ],
    );
  }
}
