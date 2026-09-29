import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/jarabes_modelos.dart';
import '../services/jarabes_service.dart';

/// Resuelve una receta propuesta. El cambio de receta lo aprueban Control
/// de Calidad Y Jefe de Producción por separado (cada uno ve un botón solo
/// si le falta dar su visto bueno); con las dos, el Gerente la activa
/// reingresando su clave. Cualquiera de los tres puede rechazarla en
/// cualquier momento, con motivo.
class ResolverRecetaDialog extends StatefulWidget {
  final JarabesService servicio;
  final RecetaPropuesta receta;
  const ResolverRecetaDialog({super.key, required this.servicio, required this.receta});

  @override
  State<ResolverRecetaDialog> createState() => _ResolverRecetaDialogState();
}

class _ResolverRecetaDialogState extends State<ResolverRecetaDialog> {
  final _motivo = TextEditingController();
  final _clave = TextEditingController();
  bool _rechazando = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ejecutar(Future<String?> Function() accion, String mensajeExito) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await accion();
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, mensajeExito);
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  Widget _estadoVisto(String etiqueta, bool dado, String? porNombre, DateTime? en) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(dado ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18, color: dado ? const Color(0xFF16A34A) : Colors.black38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dado ? '$etiqueta: $porNombre · ${fmtFechaHora(en)}' : '$etiqueta: pendiente',
              style: TextStyle(color: dado ? Colors.black87 : Colors.black54),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final svc = widget.servicio;
    final r = widget.receta;
    final puedeRechazar =
        svc.puedeAprobarComoCalidad || svc.puedeAprobarComoProduccion || svc.puedeConfirmarComoGerente;

    return AlertDialog(
      title: Text('Receta de ${r.sabor ?? ''}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Propuesta por ${r.creadaPorNombre ?? '—'} · ${fmtFechaHora(r.creadaEn)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            for (final i in r.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(i.detalle)),
                    Text('${fmtNum(i.cantidad, decimales: 3)} ${i.unidad}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text('Cambio de receta: requiere ambos vistos buenos y la clave del Gerente.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _estadoVisto('Control de Calidad', r.tieneVistoBuenoCalidad,
                r.aprobadaCalidadNombre, r.aprobadaCalidadEn),
            _estadoVisto('Jefe de Producción', r.tieneVistoBuenoProduccion,
                r.aprobadaProduccionNombre, r.aprobadaProduccionEn),
            const SizedBox(height: 12),
            if (svc.puedeAprobarComoCalidad && !r.tieneVistoBuenoCalidad)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: _guardando
                      ? null
                      : () => _ejecutar(
                          () => svc.aprobarComoCalidad(r), 'Visto bueno de Calidad registrado.'),
                  child: const Text('Dar visto bueno (Calidad)'),
                ),
              ),
            if (svc.puedeAprobarComoProduccion && !r.tieneVistoBuenoProduccion)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: _guardando
                        ? null
                        : () => _ejecutar(() => svc.aprobarComoProduccion(r),
                            'Visto bueno de Producción registrado.'),
                    child: const Text('Dar visto bueno (Producción)'),
                  ),
                ),
              ),
            if (svc.puedeConfirmarComoGerente) ...[
              const SizedBox(height: 8),
              if (!r.listaParaGerente)
                const Text('Falta algún visto bueno para poder confirmarla.',
                    style: TextStyle(fontSize: 12, color: Colors.black54))
              else ...[
                TextField(
                  controller: _clave,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Tu clave (Gerente)',
                    isDense: true,
                    helperText: 'Se vuelve a pedir para confirmar el cambio de receta.',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: _guardando
                        ? null
                        : () => _ejecutar(() => svc.confirmarComoGerente(r, _clave.text),
                            'Receta confirmada y activada.'),
                    child: const Text('Confirmar y activar'),
                  ),
                ),
              ],
            ],
            if (puedeRechazar) ...[
              const Divider(height: 24),
              TextField(
                controller: _motivo,
                maxLength: 300,
                maxLines: 2,
                enabled: _rechazando,
                decoration: const InputDecoration(
                  labelText: 'Motivo de rechazo',
                  counterText: '',
                  helperText: 'Obligatorio si vas a rechazar.',
                ),
              ),
            ],
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
          child: const Text('Cerrar'),
        ),
        if (puedeRechazar)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: _guardando
                ? null
                : () {
                    if (!_rechazando) {
                      setState(() => _rechazando = true);
                      return;
                    }
                    _ejecutar(() => svc.rechazarReceta(r, _motivo.text), 'Receta rechazada.');
                  },
            child: Text(_rechazando ? 'Confirmar rechazo' : 'Rechazar'),
          ),
      ],
    );
  }
}
