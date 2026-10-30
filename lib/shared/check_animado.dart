import 'package:flutter/material.dart';

/// ✓ que se dibuja trazo a trazo (como el "completado" de otras apps): primero
/// el tramo corto, después el largo. Se anima una vez al aparecer.
class CheckAnimado extends StatefulWidget {
  final double tamano;
  final Color color;
  final double grosor;
  final Duration duracion;
  const CheckAnimado({
    super.key,
    this.tamano = 24,
    this.color = const Color(0xFF16A34A),
    this.grosor = 3,
    this.duracion = const Duration(milliseconds: 550),
  });

  @override
  State<CheckAnimado> createState() => _CheckAnimadoState();
}

class _CheckAnimadoState extends State<CheckAnimado> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duracion)..forward();
  late final _avance = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.tamano,
        child: AnimatedBuilder(
          animation: _avance,
          builder: (_, __) => CustomPaint(
            painter: _PintorCheck(_avance.value, widget.color, widget.grosor),
          ),
        ),
      );
}

class _PintorCheck extends CustomPainter {
  final double avance;
  final Color color;
  final double grosor;
  _PintorCheck(this.avance, this.color, this.grosor);

  @override
  void paint(Canvas canvas, Size s) {
    final a = Offset(s.width * 0.18, s.height * 0.54);
    final b = Offset(s.width * 0.42, s.height * 0.76);
    final c = Offset(s.width * 0.84, s.height * 0.28);
    final corto = (b - a).distance;
    final largo = (c - b).distance;
    final hecho = avance * (corto + largo);
    final path = Path()..moveTo(a.dx, a.dy);
    if (hecho <= corto) {
      final p = Offset.lerp(a, b, hecho / corto)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, c, (hecho - corto) / largo)!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = grosor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PintorCheck o) => o.avance != avance;
}
