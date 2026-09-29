import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Fondo de video en loop que cubre todo el espacio disponible (comportamiento
/// tipo CSS `object-fit: cover`), sin deformarse ni afectar el layout del
/// contenido que se dibuje encima al cambiar de tamaño (ej. mobile).
class VideoBackground extends StatefulWidget {
  const VideoBackground({super.key, required this.asset});

  final String asset;

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  late final VideoPlayerController _controller;
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.asset);
    _controller
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _listo = true);
        _controller.play();
      }).catchError((_) {
        // Si el video no puede reproducirse (formato no soportado en la
        // plataforma, etc.) se deja el fondo sin video; el llamador siempre
        // debe poner un color/gradiente detrás de este widget como respaldo.
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_listo || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
