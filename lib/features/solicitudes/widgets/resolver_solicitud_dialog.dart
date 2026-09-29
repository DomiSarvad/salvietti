import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/notificaciones.dart';
import '../models/solicitud.dart';
import '../services/solicitudes_service.dart';

/// Gerencia aprueba o rechaza una solicitud pendiente, con una respuesta
/// opcional (obligatoria si se rechaza).
class ResolverSolicitudDialog extends StatefulWidget {
  final SolicitudesService servicio;
  final Solicitud solicitud;
  const ResolverSolicitudDialog({super.key, required this.servicio, required this.solicitud});

  @override
  State<ResolverSolicitudDialog> createState() => _ResolverSolicitudDialogState();
}

class _ResolverSolicitudDialogState extends State<ResolverSolicitudDialog> {
  final _respuesta = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _respuesta.dispose();
    super.dispose();
  }

  Future<void> _resolver(bool aprobar) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = aprobar
        ? await widget.servicio.aprobar(widget.solicitud, respuesta: _respuesta.text)
        : await widget.servicio.rechazar(widget.solicitud, _respuesta.text);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, aprobar ? 'Solicitud aprobada.' : 'Solicitud rechazada.');
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
    final s = widget.solicitud;
    return AlertDialog(
      title: Text('Solicitud de ${s.solicitanteNombre ?? '—'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TipoSolicitud.etiqueta(s.tipo),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(s.asunto, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (s.itemDetalle != null) ...[
              const SizedBox(height: 6),
              Text('Ítem: ${s.itemDetalle}'
                  '${s.cantidadSugerida == null ? '' : ' · ${s.cantidadSugerida} ${s.itemUnidad ?? ''}'}'),
            ],
            if (s.detalle != null) ...[
              const SizedBox(height: 6),
              Text(s.detalle!),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _respuesta,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Respuesta',
                counterText: '',
                helperText: 'Obligatoria si vas a rechazar.',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
          onPressed: _guardando ? null : () => _resolver(false),
          child: const Text('Rechazar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
          onPressed: _guardando ? null : () => _resolver(true),
          child: Text(_guardando ? 'Guardando…' : 'Aprobar'),
        ),
      ],
    );
  }
}
