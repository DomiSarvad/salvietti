import 'dart:ui' as ui;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../utils/formatters.dart';

/// Vista previa de una tabla limpia (sin botones ni iconos de la app)
/// para capturarla como imagen y compartirla por WhatsApp con los
/// operarios de planta, que no tienen acceso al sistema — tal como hoy
/// lo hacen a mano con una captura de su planilla.
class ProduccionCapturaDialog extends StatefulWidget {
  final PlanProduccion plan;
  const ProduccionCapturaDialog({super.key, required this.plan});

  @override
  State<ProduccionCapturaDialog> createState() => _ProduccionCapturaDialogState();
}

class _ProduccionCapturaDialogState extends State<ProduccionCapturaDialog> {
  final _capturaKey = GlobalKey();
  bool _guardando = false;
  String? _mensaje;

  Future<void> _compartir() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    try {
      final boundary = _capturaKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se pudo preparar la imagen.');
      final imagen = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await imagen.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar el PNG.');
      final bytes = byteData.buffer.asUint8List();
      final nombre = 'produccion_${fmtFecha(widget.plan.fecha).replaceAll('/', '-')}';

      // Primero se intenta el panel nativo de compartir (WhatsApp,
      // Bluetooth, etc.) — funciona en celular y en la mayoría de los
      // navegadores. Si la plataforma no lo soporta (ej. escritorio sin
      // panel de compartir), se guarda directo en el dispositivo como
      // respaldo, en vez de mostrar un error.
      try {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: '$nombre.png')],
          text: 'Producción del día — ${fmtFecha(widget.plan.fecha)}',
        );
        setState(() => _mensaje = 'Listo para compartir.');
      } catch (_) {
        await FileSaver.instance.saveFile(
          name: nombre,
          bytes: bytes,
          ext: 'png',
          mimeType: MimeType.png,
        );
        setState(() => _mensaje =
            'Tu dispositivo no tiene panel de compartir: se guardó la imagen '
            'localmente. Ya la podés adjuntar en WhatsApp a mano.');
      }
    } catch (e) {
      setState(() => _mensaje = 'No se pudo generar la imagen: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return AlertDialog(
      title: const Text('Vista previa para compartir'),
      // La tabla capturada mantiene un ancho fijo (para que la imagen
      // compartida se vea prolija en cualquier dispositivo); en pantallas
      // angostas la VISTA PREVIA se desplaza horizontalmente en vez de
      // achicarla, así nunca se desborda.
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
        child: RepaintBoundary(
          key: _capturaKey,
          child: Container(
            width: 420,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset('assets/logo.jpg', height: 32, width: 32),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Producción del día',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(fmtFecha(plan.fecha),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(2.5),
                    2: FlexColumnWidth(1.8),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: AppColors.primario),
                      children: const [
                        _Celda('Producto', esEncabezado: true),
                        _Celda('Cantidad', esEncabezado: true),
                        _Celda('Estado', esEncabezado: true),
                      ],
                    ),
                    for (final d in plan.detalle)
                      TableRow(children: [
                        _Celda(d.nombreProducto ?? d.sabor),
                        _Celda(d.completado
                            ? '${fmtNum(d.botellasProducidas, decimales: 0)} botellas'
                                '${d.litrosProducidos != null ? ' · ${fmtNum(d.litrosProducidos, decimales: 0)} L' : ''}'
                            : '${fmtNum(d.litrosPlanificados, decimales: 0)} L planificados'),
                        _Celda(d.completado ? 'Hecho ✓' : 'Pendiente'),
                      ]),
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
      actions: [
        if (_mensaje != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_mensaje!,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
        FilledButton.icon(
          onPressed: _guardando ? null : _compartir,
          icon: _guardando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share, size: 18),
          label: const Text('Compartir'),
        ),
      ],
    );
  }
}

class _Celda extends StatelessWidget {
  final String texto;
  final bool esEncabezado;
  const _Celda(this.texto, {this.esEncabezado = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: esEncabezado ? FontWeight.bold : FontWeight.normal,
          color: esEncabezado ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
