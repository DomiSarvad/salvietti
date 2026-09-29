import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../models/recepciones_modelos.dart';
import '../services/recepciones_service.dart';

/// Detalle de una recepción guardada, con la foto de respaldo si la tiene.
class RecepcionDetalleDialog extends StatelessWidget {
  final RecepcionesService servicio;
  final RecepcionDetalle r;
  const RecepcionDetalleDialog({super.key, required this.servicio, required this.r});

  Widget _fila(String etiqueta, String? valor) => valor == null || valor.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 130,
                  child: Text(etiqueta,
                      style: const TextStyle(color: Colors.black54, fontSize: 13))),
              Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );

  @override
  Widget build(BuildContext context) {
    final sinDif = r.diferencia.abs() < 1e-9;
    final colorDif = sinDif
        ? const Color(0xFF16A34A)
        : (r.diferencia < 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.detalle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              Text('${r.codigo} · Recepción del ${fmtFecha(r.fecha)}',
                  style: const TextStyle(color: Colors.black54)),
              const Divider(height: 24),
              _fila('Proveedor', r.proveedor),
              _fila('N° de factura', r.nFactura),
              _fila('Según factura', '${fmtNum(r.cantidadFactura, decimales: 3)} ${r.unidad}'),
              _fila('Real (pesado)', '${fmtNum(r.cantidadReal, decimales: 3)} ${r.unidad}'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const SizedBox(
                      width: 130,
                      child: Text('Diferencia',
                          style: TextStyle(color: Colors.black54, fontSize: 13))),
                  Text(
                    sinDif
                        ? 'Sin diferencia'
                        : '${r.diferencia > 0 ? '+' : ''}${fmtNum(r.diferencia, decimales: 3)} ${r.unidad}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorDif),
                  ),
                ]),
              ),
              _fila('N° de lote', r.nLote),
              _fila('Fabricación', r.fechaFabricacion == null ? null : fmtFecha(r.fechaFabricacion)),
              _fila('Vencimiento', r.fechaVencimiento == null ? null : fmtFecha(r.fechaVencimiento)),
              _fila('SENASAG', r.senasac),
              _fila('Transportador', r.transportador),
              _fila('Precio transporte',
                  r.precioTransporte == null ? null : 'Bs ${fmtNum(r.precioTransporte)}'),
              _fila('Observaciones', r.observaciones),
              if (r.fotoUrl != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: servicio.urlFoto(r.fotoUrl!),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final url = snap.data;
                    if (url == null) {
                      return const Text('No se pudo cargar la foto.',
                          style: TextStyle(color: Colors.black54));
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('No se pudo mostrar la foto.'),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.primario),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
