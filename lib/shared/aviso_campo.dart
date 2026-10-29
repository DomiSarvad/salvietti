import 'dart:async';
import 'package:flutter/material.dart';

OverlayEntry? _actual;
Timer? _cierre;

/// Señala el campo que falta o está mal con un globo debajo (ícono "!" y el
/// mensaje), como la validación de un navegador: primero lo trae a la vista,
/// después muestra el globo unos segundos. [clave] es la del campo.
Future<void> avisarCampo(GlobalKey clave, String mensaje) async {
  final ctx = clave.currentContext;
  if (ctx == null) return;
  await Scrollable.ensureVisible(ctx,
      alignment: 0.3, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  final caja = clave.currentContext?.findRenderObject() as RenderBox?;
  final ctxActual = clave.currentContext;
  if (caja == null || !caja.hasSize || ctxActual == null || !ctxActual.mounted) return;
  final overlay = Overlay.maybeOf(ctxActual, rootOverlay: true);
  if (overlay == null) return;

  _quitar();
  final arriba = caja.localToGlobal(Offset.zero);
  final ancho = MediaQuery.sizeOf(ctxActual).width;
  final izquierda = (arriba.dx + 12).clamp(8.0, (ancho - 260).clamp(8.0, ancho));
  _actual = OverlayEntry(
    builder: (_) => Positioned(
      left: izquierda,
      top: arriba.dy + caja.size.height - 4,
      child: GestureDetector(onTap: _quitar, child: _Globo(mensaje: mensaje)),
    ),
  );
  overlay.insert(_actual!);
  _cierre = Timer(const Duration(seconds: 3), _quitar);
}

void _quitar() {
  _cierre?.cancel();
  _cierre = null;
  _actual?.remove();
  _actual = null;
}

class _Globo extends StatelessWidget {
  final String mensaje;
  const _Globo({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        builder: (_, v, hijo) => Opacity(opacity: v, child: hijo),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Piquito apuntando al campo.
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: CustomPaint(size: const Size(14, 8), painter: _Pico()),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFBDBDBD)),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8600A),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(Icons.priority_high_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(mensaje, style: const TextStyle(fontSize: 14, color: Colors.black87))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pico extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height),
        Paint()
          ..color = const Color(0xFFBDBDBD)
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
