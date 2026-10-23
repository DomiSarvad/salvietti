import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Muestra una foto agrandada sobre fondo oscuro, como al tocar la foto de
/// una cuenta de Google: se puede acercar (dos dedos, doble toque o rueda del
/// mouse con Ctrl) y se cierra tocando afuera, con la "X" o con Escape.
///
/// [tag] es el `Hero` de la miniatura: si se pasa el mismo en los dos lados,
/// la foto "crece" desde el círculo en vez de aparecer de golpe.
Future<void> mostrarFotoAmpliada(
  BuildContext context, {
  required ImageProvider imagen,
  String? titulo,
  Object? tag,
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _VisorFoto(imagen: imagen, titulo: titulo, tag: tag),
    transitionsBuilder: (_, animacion, __, hijo) =>
        FadeTransition(opacity: animacion, child: hijo),
  ));
}

class _VisorFoto extends StatefulWidget {
  final ImageProvider imagen;
  final String? titulo;
  final Object? tag;
  const _VisorFoto({required this.imagen, this.titulo, this.tag});

  @override
  State<_VisorFoto> createState() => _VisorFotoState();
}

class _VisorFotoState extends State<_VisorFoto> {
  final _zoom = TransformationController();
  TapDownDetails? _dobleToque;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  /// Doble toque: acerca al doble donde se tocó; otro doble toque vuelve.
  void _alternarZoom() {
    if (_zoom.value != Matrix4.identity()) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final p = _dobleToque?.localPosition ?? Offset.zero;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx, -p.dy, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final tam = MediaQuery.sizeOf(context);
    // Cuadrada (las fotos de perfil se guardan recortadas a 512 px) y sin
    // pasarse de la pantalla, con margen.
    final lado = (tam.shortestSide - 48).clamp(160.0, 560.0);

    Widget foto = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: widget.imagen,
        width: lado,
        height: lado,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox(
          width: lado,
          height: lado,
          child: const Center(
            child: Text('No se pudo cargar la foto.', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
    if (widget.tag != null) foto = Hero(tag: widget.tag!, child: foto);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              // Tocar el fondo (fuera de la foto) cierra.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                ),
              ),
              Center(
                child: GestureDetector(
                  onDoubleTapDown: (d) => _dobleToque = d,
                  onDoubleTap: _alternarZoom,
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    minScale: 1,
                    maxScale: 4,
                    child: foto,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      if (widget.titulo != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(widget.titulo!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                        )
                      else
                        const Spacer(),
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
