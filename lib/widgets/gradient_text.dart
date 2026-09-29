import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Texto con degradado de marca (verde→negro por defecto): el mismo
/// efecto que un logo/título "dinámico" en vez de un color plano.
class GradientText extends StatelessWidget {
  final String texto;
  final TextStyle style;
  final Gradient gradiente;
  const GradientText(this.texto,
      {super.key, required this.style, this.gradiente = AppColors.gradientePrincipal});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => gradiente.createShader(rect),
      child: Text(texto, style: style),
    );
  }
}
