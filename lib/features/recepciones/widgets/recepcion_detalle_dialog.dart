import 'package:flutter/material.dart';
import '../../../shared/pagina_detalle.dart';
import '../../../shared/visor_foto.dart';
import '../../../utils/formatters.dart';
import '../models/recepciones_modelos.dart';
import '../services/recepciones_service.dart';

/// Detalle de una recepción guardada (página con barra negra), con la foto de
/// respaldo si la tiene.
class RecepcionDetalleDialog extends StatelessWidget {
  final RecepcionesService servicio;
  final RecepcionDetalle r;
  const RecepcionDetalleDialog({super.key, required this.servicio, required this.r});

  static Future<void> abrir(BuildContext context, RecepcionesService servicio, RecepcionDetalle r) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecepcionDetalleDialog(servicio: servicio, r: r),
      ));

  @override
  Widget build(BuildContext context) {
    final sinDif = r.diferencia.abs() < 1e-9;
    final colorDif = sinDif
        ? const Color(0xFF16A34A)
        : (r.diferencia < 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706));
    String cant(double v) => '${fmtNum(v, decimales: 3)} ${r.unidad}';

    return PaginaDetalle(
      titulo: r.detalle,
      subtitulo: '${r.codigo} · Recepción del ${fmtFecha(r.fecha)}',
      estado: sinDif
          ? 'Llegó completo'
          : r.diferencia < 0
              ? 'Faltó ${cant(-r.diferencia)}'
              : 'Sobró ${cant(r.diferencia)}',
      colorEstado: colorDif,
      secciones: [
        SeccionDetalle(titulo: 'Cantidades', filas: [
          ('Según factura', cant(r.cantidadFactura)),
          ('Real (pesado)', cant(r.cantidadReal)),
          ('Diferencia', sinDif ? 'Sin diferencia' : '${r.diferencia > 0 ? '+' : ''}${cant(r.diferencia)}'),
        ]),
        SeccionDetalle(titulo: 'Proveedor y factura', filas: [
          ('Proveedor', r.proveedor),
          ('N° de factura', r.nFactura),
          ('Transportador', r.transportador),
          ('Precio transporte', r.precioTransporte == null ? null : 'Bs ${fmtNum(r.precioTransporte)}'),
        ]),
        SeccionDetalle(titulo: 'Lote', filas: [
          ('N° de lote', r.nLote),
          ('Fabricación', r.fechaFabricacion == null ? null : fmtFecha(r.fechaFabricacion)),
          ('Vencimiento', r.fechaVencimiento == null ? null : fmtFecha(r.fechaVencimiento)),
          ('SENASAG', r.senasac),
        ]),
        SeccionDetalle(filas: [('Observaciones', r.observaciones)]),
      ],
      extra: [
        if (r.fotos.isNotEmpty) ...[
          Text(r.fotos.length == 1 ? 'Foto' : 'Fotos (${r.fotos.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
        ],
        // Casilleros con su nombre, como en el formulario; tocar uno la amplía.
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < r.fotos.length; i++)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Foto ${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Container(
                width: 120,
                height: 120,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD5DADF)),
                ),
                child: FutureBuilder<String?>(
                  future: servicio.urlFoto(r.fotos[i]),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final url = snap.data;
                    if (url == null) {
                      return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.black26));
                    }
                    return InkWell(
                      onTap: () => mostrarFotoAmpliada(context,
                          imagen: NetworkImage(url), titulo: 'Foto ${i + 1}', tag: url),
                      child: Hero(
                        tag: url,
                        child: Image.network(url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Icon(Icons.broken_image_outlined, color: Colors.black26))),
                      ),
                    );
                  },
                ),
              ),
            ]),
        ]),
      ],
    );
  }
}
