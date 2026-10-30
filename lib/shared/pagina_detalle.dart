import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../utils/notificaciones.dart';
import 'reportes/comprobante_pdf.dart';

/// Página de detalle de un registro (tocar una tarjeta de un historial): barra
/// negra con título y subtítulo, un recuadro con el estado y los datos en
/// bloques "etiqueta — valor". Misma forma en todos los módulos.
///
/// Con [nombrePdf], la barra tiene un botón que baja un comprobante PDF con
/// los MISMOS datos (estado, secciones y [tablasPdf]): para lo que pasa entre
/// dos áreas (un pedido, una compra, una receta), por si hace falta en papel.
class PaginaDetalle extends StatelessWidget {
  final String titulo;
  final String? subtitulo;

  /// Estado destacado arriba (ej. "Finalizada"), con su color.
  final String? estado;
  final Color? colorEstado;
  final List<SeccionDetalle> secciones;

  /// Lo que no es "etiqueta — valor" (listas, botones), al final.
  final List<Widget> extra;

  /// Nombre del archivo del comprobante; null = sin botón de PDF.
  final String? nombrePdf;

  /// Lo que en pantalla va en [extra] y en el PDF como tabla (ej. ítems).
  final List<TablaComprobante> tablasPdf;
  final List<String> firmasPdf;

  const PaginaDetalle({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.estado,
    this.colorEstado,
    this.secciones = const [],
    this.extra = const [],
    this.nombrePdf,
    this.tablasPdf = const [],
    this.firmasPdf = const [],
  });

  /// Abre la página encima de la pantalla actual.
  static Future<void> abrir(BuildContext context, PaginaDetalle pagina) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));

  Future<void> _pdf(BuildContext context) async {
    try {
      final bytes = await ComprobantePdf.generar(
        titulo: titulo,
        subtitulo: subtitulo,
        estado: estado,
        colorEstado: colorEstado?.toARGB32(),
        secciones: [for (final s in secciones) (s.titulo, s.filas)],
        tablas: tablasPdf,
        firmas: firmasPdf,
      );
      final msg = await ComprobantePdf.guardar(bytes, nombrePdf!);
      if (context.mounted) mostrarInfo(context, msg);
    } catch (_) {
      if (context.mounted) mostrarError(context, 'No se pudo generar el PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorEstado ?? AppColors.primario;
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: barraNegra(titulo, subtitulo, [
        if (nombrePdf != null)
          IconButton(
            tooltip: 'Comprobante en PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _pdf(context),
          ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (estado != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(estado!, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final s in secciones) ...[s, const SizedBox(height: 12)],
        ...extra,
      ]),
    );
  }
}

/// Barra negra de las páginas de detalle (con subtítulo chico debajo).
PreferredSizeWidget barraNegra(String titulo, [String? subtitulo, List<Widget>? acciones]) => AppBar(
      backgroundColor: AppColors.negro,
      surfaceTintColor: AppColors.negro,
      foregroundColor: Colors.white,
      actions: acciones,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (subtitulo != null)
          Text(subtitulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
    );

/// Un bloque de datos con título opcional. Las filas con valor nulo o vacío
/// no se muestran (así cada módulo pasa todo sin preguntar qué tiene).
class SeccionDetalle extends StatelessWidget {
  final String? titulo;
  final List<(String, String?)> filas;
  const SeccionDetalle({super.key, this.titulo, required this.filas});

  @override
  Widget build(BuildContext context) {
    final visibles = filas.where((f) => (f.$2 ?? '').trim().isNotEmpty && f.$2 != '-').toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (titulo != null) ...[
          Text(titulo!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
        ],
        for (var i = 0; i < visibles.length; i++) ...[
          if (i > 0) const Divider(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: Text(visibles[i].$1, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(visibles[i].$2!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
      ]),
    );
  }
}
