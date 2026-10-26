import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Banner de degradado verde→negro con una "X" para cerrar y espacio para
/// que el contenido (avatar, ícono) se superponga en su borde inferior —
/// mismo lenguaje visual en "Mi perfil" y "Nuevo usuario".
///
/// La parte del contenido que "cuelga" debajo del degradado ([solape]) está
/// DENTRO del alto del widget, no afuera: Flutter dibuja lo que sobresale de
/// un `Stack` con `Clip.none`, pero no le entrega toques. Antes el avatar
/// sobresalía 40 px por fuera, y el botón de la cámara de "Mi perfil" (abajo
/// a la derecha del avatar) se veía pero no se podía tocar.
class DialogBanner extends StatelessWidget {
  /// Null: sin la X (cuando es una página con su propia flecha de volver).
  final VoidCallback? onCerrar;
  final Widget child;
  const DialogBanner({super.key, this.onCerrar, required this.child});

  static const _altoDegradado = 110.0;
  static const solape = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _altoDegradado + solape,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _altoDegradado,
            child: Container(
              decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal),
            ),
          ),
          // Sin X cuando es una página: ya tiene la flecha de volver arriba.
          if (onCerrar != null)
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: onCerrar,
              ),
            ),
          Positioned(bottom: 0, child: child),
        ],
      ),
    );
  }
}

/// Cinta/etiqueta con un texto (nombre), como la ficha de usuario de
/// referencia.
class DialogRibbon extends StatelessWidget {
  final String texto;
  const DialogRibbon({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primario,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }
}

/// Decoración común para los campos de texto de estos diálogos "modernos":
/// ícono a la izquierda, fondo gris claro, sin borde visible.
InputDecoration decoracionCampoModerno(String label, IconData icono) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20),
      filled: true,
      fillColor: const Color(0xFFF4F6F8),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
