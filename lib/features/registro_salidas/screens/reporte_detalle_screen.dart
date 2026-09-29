import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/salidas_modelos.dart';
import '../services/salidas_service.dart';
import '../widgets/linea_form_dialog.dart';

/// Detalle de un reporte de salidas: sus líneas (sabor/formato) y, si está
/// abierto, agregar/editar/eliminar líneas y cerrarlo.
class ReporteDetalleScreen extends StatefulWidget {
  final SalidasService servicio;
  final ReporteSalidas reporte;
  const ReporteDetalleScreen({super.key, required this.servicio, required this.reporte});

  @override
  State<ReporteDetalleScreen> createState() => _ReporteDetalleScreenState();
}

class _ReporteDetalleScreenState extends State<ReporteDetalleScreen> {
  List<LineaSalidas> _lineas = [];
  bool _cargando = true;
  String? _error;

  /// El reporte tal como está ahora en el service (por si se cerró desde acá).
  ReporteSalidas get _reporte => widget.servicio.reportes
      .where((r) => r.id == widget.reporte.id)
      .firstOrNull ?? widget.reporte;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lineas = await widget.servicio.lineasDe(widget.reporte);
      if (!mounted) return;
      setState(() {
        _lineas = lineas;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el reporte.';
      });
    }
  }

  Future<void> _agregarOEditar([LineaSalidas? linea]) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          LineaFormDialog(servicio: widget.servicio, reporte: _reporte, linea: linea),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _eliminar(LineaSalidas linea) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del reporte'),
        content: Text('¿Quitar "${linea.sabor} · ${linea.presentacion}" de este reporte?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    final error = await widget.servicio.eliminarLinea(linea.id);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Línea eliminada.');
      await _cargar();
    } else {
      mostrarError(context, error);
    }
  }

  Future<void> _cerrar() async {
    final obs = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Cerrar reporte'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Cerrar reporte')),
          ],
        );
      },
    );
    if (obs == null || !mounted) return;
    final error = await widget.servicio.cerrarReporte(_reporte, obs.trim().isEmpty ? null : obs);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Reporte cerrado.');
      Navigator.pop(context);
    } else {
      mostrarError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reporte;
    final abierto = r.estado == EstadoReporte.abierto;
    final puedeEditar = widget.servicio.puedeEditar && abierto;

    return Scaffold(
      appBar: AppBar(
        title: Text('Reporte · ${r.turno.etiqueta} · ${fmtFecha(r.fecha)}'),
        actions: [
          if (puedeEditar)
            TextButton(
              onPressed: _cerrar,
              child: const Text('Cerrar reporte', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: puedeEditar
          ? FloatingActionButton.extended(
              onPressed: () => _agregarOEditar(),
              backgroundColor: AppColors.primario,
              icon: const Icon(Icons.add),
              label: const Text('Agregar sabor'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    if (!abierto)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          'Reporte cerrado${r.horaFinDia == null ? '' : ' · ${fmtFechaHora(r.horaFinDia)}'}'
                          '${r.observaciones == null ? '' : ' · ${r.observaciones}'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    if (_lineas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: Text('Todavía no se agregó ningún sabor a este reporte.',
                                style: TextStyle(color: Colors.black54))),
                      )
                    else
                      for (final l in _lineas) _TarjetaLinea(
                        linea: l,
                        puedeEditar: puedeEditar,
                        onEditar: () => _agregarOEditar(l),
                        onEliminar: () => _eliminar(l),
                      ),
                  ],
                ),
    );
  }
}

class _TarjetaLinea extends StatelessWidget {
  final LineaSalidas linea;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  const _TarjetaLinea({
    required this.linea,
    required this.puedeEditar,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final l = linea;
    final detalle = l.esPet
        ? '${fmtNum(l.petPalets ?? 0, decimales: 0)} palets + '
            '${fmtNum(l.petPaquetesLibres ?? 0, decimales: 0)} paquetes + '
            '${fmtNum(l.petBotellasLibres ?? 0, decimales: 0)} sueltas'
        : '${fmtNum(l.vidFilas ?? 0, decimales: 0)} filas + '
            '${fmtNum(l.vidCajasLibres ?? 0, decimales: 0)} cajas + '
            '${fmtNum(l.vidBotellasLibres ?? 0, decimales: 0)} sueltas';

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
                  child: Text('${l.sabor} · ${l.presentacion}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(l.esPet ? 'PET' : 'Vidrio',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 4),
            Text(detalle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              l.totalBotellas == null
                  ? 'Total: — (falta la equivalencia de esta presentación)'
                  : 'Total: ${fmtNum(l.totalBotellas, decimales: 0)} botellas',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: l.totalBotellas == null ? Colors.black38 : AppColors.primario),
            ),
            if (puedeEditar) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: onEditar, child: const Text('Editar')),
                TextButton(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                    onPressed: onEliminar,
                    child: const Text('Quitar')),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
