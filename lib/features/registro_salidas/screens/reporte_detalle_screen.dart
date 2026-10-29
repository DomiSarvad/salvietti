import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import '../../../core/constants.dart';
import '../../../shared/pagina_detalle.dart';
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
    final ok = await confirmar(
      context,
      titulo: '¿Quitar del reporte?',
      texto: '${linea.sabor} · ${linea.presentacion}',
      textoSi: 'Sí, quitar',
      peligro: true,
    );
    if (!ok) return;
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
    final obs = await confirmarConMotivo(
      context,
      titulo: '¿Cerrar el reporte?',
      texto: 'Ya no se podrán agregar ni cambiar sabores.',
      textoSi: 'Sí, cerrar',
      etiqueta: 'Observaciones (opcional)',
      obligatorio: false,
      peligro: false,
      tipo: TipoAlerta.pregunta,
    );
    if (obs == null || !mounted) return;
    final error = await widget.servicio.cerrarReporte(_reporte, obs.trim().isEmpty ? null : obs);
    if (!mounted) return;
    if (error == null) {
      avisoExito(context, 'Reporte cerrado');
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

    final total = _lineas.fold<double>(0, (s, l) => s + (l.totalBotellas ?? 0));
    final colorEstado = abierto ? const Color(0xFFD97706) : const Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: barraNegra('Reporte de salidas', 'Turno ${r.turno.etiqueta} · ${fmtFecha(r.fecha)}'),
      // Los botones abajo, a la vista (antes "Cerrar reporte" iba en blanco
      // sobre una barra clara y no se veía).
      bottomNavigationBar: puedeEditar
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
                ),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lineas.isEmpty ? null : _cerrar,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Cerrar reporte'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                      onPressed: () => _agregarOEditar(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar sabor'),
                    ),
                  ),
                ]),
              ),
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
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Resumen: en qué estado está y cuánto salió en total.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3E7EB)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorEstado.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(abierto ? 'Abierto' : 'Cerrado',
                                style: TextStyle(color: colorEstado, fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          Text('${_lineas.length} sabor${_lineas.length == 1 ? '' : 'es'}',
                              style: const TextStyle(color: Colors.black54)),
                        ]),
                        const SizedBox(height: 12),
                        const Text('Botellas que salieron en este turno',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Text(fmtNum(total, decimales: 0),
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.primario)),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (r.responsableNombre != null) r.responsableNombre!,
                            'Desde ${fmtFechaHora(r.horaInicioDia)}',
                            if (r.horaFinDia != null) 'hasta ${fmtFechaHora(r.horaFinDia)}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        if ((r.observaciones ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Observaciones: ${r.observaciones}', style: const TextStyle(fontSize: 13)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    if (_lineas.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(children: [
                          const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.black26),
                          const SizedBox(height: 8),
                          Text(
                            puedeEditar
                                ? 'Agregá cada sabor que se embotelló en este turno.'
                                : 'Este reporte no tiene sabores cargados.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ]),
                      )
                    else ...[
                      const Text('Sabores',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      for (final l in _lineas)
                        _TarjetaLinea(
                          linea: l,
                          puedeEditar: puedeEditar,
                          onEditar: () => _agregarOEditar(l),
                          onEliminar: () => _eliminar(l),
                        ),
                    ],
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
    // Cómo se contó (solo lo que tiene algo): "2 palets · 5 paquetes".
    String? parte(double? v, String nombre) =>
        (v ?? 0) > 0 ? '${fmtNum(v, decimales: 0)} $nombre' : null;
    final conteo = [
      if (l.esPet) ...[
        parte(l.petPalets, 'palets'),
        parte(l.petPaquetesLibres, 'paquetes'),
        parte(l.petBotellasLibres, 'sueltas'),
      ] else ...[
        parte(l.vidFilas, 'filas'),
        parte(l.vidCajasLibres, 'cajas'),
        parte(l.vidBotellasLibres, 'sueltas'),
      ],
    ].whereType<String>().join(' · ');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE3E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Tocar la tarjeta la edita (mientras el reporte está abierto).
        onTap: puedeEditar ? onEditar : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.sabor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('${l.presentacion} · ${l.esPet ? 'PET' : 'Vidrio'}',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                if (conteo.isNotEmpty)
                  Text(conteo, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(l.totalBotellas == null ? '—' : fmtNum(l.totalBotellas, decimales: 0),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: l.totalBotellas == null ? Colors.black38 : AppColors.primario)),
              Text(l.totalBotellas == null ? 'sin equivalencia' : 'botellas',
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ]),
            if (puedeEditar)
              IconButton(
                tooltip: 'Quitar del reporte',
                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                onPressed: onEliminar,
              ),
          ]),
        ),
      ),
    );
  }
}
