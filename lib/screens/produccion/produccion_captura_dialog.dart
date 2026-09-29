import 'dart:ui' as ui;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../models/usuario.dart';
import '../../utils/formatters.dart';

/// Vista previa de una tabla limpia (sin botones ni iconos de la app, y sin
/// la columna "Eliminar" que sí existe al armar el plan) para capturarla
/// como imagen y compartirla por WhatsApp con los operarios de planta, que
/// no tienen acceso al sistema — tal como hoy lo hacen a mano con una
/// captura de su planilla.
class ProduccionCapturaDialog extends StatefulWidget {
  final PlanProduccion plan;
  final Usuario usuario;
  const ProduccionCapturaDialog(
      {super.key, required this.plan, required this.usuario});

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
    final completados = plan.detalle.where((d) => d.completado).toList();
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
            width: 620,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Image.asset('assets/logo.png', height: 32, width: 32),
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
                    0: FlexColumnWidth(0.5),
                    1: FlexColumnWidth(2.6),
                    2: FlexColumnWidth(1.4),
                    3: FlexColumnWidth(1.1),
                    4: FlexColumnWidth(1.4),
                    5: FlexColumnWidth(1.3),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: AppColors.primario),
                      children: const [
                        _Celda('N°', esEncabezado: true),
                        _Celda('Producto', esEncabezado: true),
                        _Celda('Paquetes/Cajas', esEncabezado: true),
                        _Celda('Botellas', esEncabezado: true),
                        _Celda('Total botellas', esEncabezado: true),
                        _Celda('Total litros', esEncabezado: true),
                      ],
                    ),
                    for (final (i, d) in plan.detalle.indexed)
                      TableRow(children: [
                        _Celda('${i + 1}'),
                        _Celda(d.nombreProducto ?? d.sabor),
                        _Celda(fmtNum(_paquetesCajas(d), decimales: 0)),
                        _Celda(fmtNum(_botellasSueltas(d), decimales: 0)),
                        _Celda(fmtNum(_totalBotellas(d), decimales: 0)),
                        _Celda(fmtNum(d.litrosPlanificados, decimales: 2)),
                      ]),
                  ],
                ),
                if (completados.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(0.5),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(1.5),
                    },
                    children: [
                      TableRow(
                        decoration:
                            const BoxDecoration(color: AppColors.primario),
                        children: const [
                          _Celda('N°', esEncabezado: true),
                          _Celda('Sabor', esEncabezado: true),
                          _Celda('Total producido (litros)', esEncabezado: true),
                          _Celda('Merma (litros)', esEncabezado: true),
                        ],
                      ),
                      for (final (i, d) in completados.indexed)
                        TableRow(children: [
                          _Celda('${i + 1}'),
                          _Celda(d.sabor),
                          _Celda(fmtNum(d.litrosProducidos, decimales: 2)),
                          _Celda(fmtNum(d.mermaLitros, decimales: 2)),
                        ]),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  color: AppColors.primario,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Usuario: ${widget.usuario.nombreCompleto}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                      Text('Perfil: ${Rol.etiqueta(widget.usuario.rol)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ],
                  ),
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

  /// Total de botellas planificadas, a partir de los litros (no se
  /// persiste el desglose de paquetes/botellas que cargó el ingeniero al
  /// armar el plan, así que se recalcula con la misma fórmula inversa).
  double _totalBotellas(PlanProduccionDetalle d) {
    if (d.litrosPorBotella == null || d.litrosPorBotella! <= 0) return 0;
    return d.litrosPlanificados / d.litrosPorBotella!;
  }

  // Si el producto vende por paquete/caja, el ingeniero siempre carga
  // "Paquetes/Cajas" (nunca "Botellas" sueltas para ese producto, y
  // viceversa) — mismo criterio que ConstructorPlanDialog.
  double _paquetesCajas(PlanProduccionDetalle d) {
    if (d.botellasPorPaquete == null || d.botellasPorPaquete! <= 0) return 0;
    return _totalBotellas(d) / d.botellasPorPaquete!;
  }

  double _botellasSueltas(PlanProduccionDetalle d) {
    if (d.botellasPorPaquete != null) return 0;
    return _totalBotellas(d);
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
