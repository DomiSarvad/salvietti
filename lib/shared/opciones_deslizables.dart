import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Opciones para elegir una (almacén, bandeja, estado…) en UNA sola fila que
/// se desliza de costado, como las áreas de Informes: con muchas opciones no
/// ocupan varias líneas de la pantalla.
class OpcionesDeslizables<T> extends StatelessWidget {
  final List<T> opciones;
  final T seleccionada;
  final String Function(T) etiqueta;
  final IconData? Function(T)? icono;
  final ValueChanged<T> onElegir;

  const OpcionesDeslizables({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.etiqueta,
    required this.onElegir,
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in opciones)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Opcion(
              etiqueta: etiqueta(o),
              icono: icono?.call(o),
              elegida: o == seleccionada,
              onTap: () => onElegir(o),
            ),
          ),
      ]),
    );
  }
}

/// La elegida con el degradado verde y su brillo (como el botón de
/// sincronización de la barra superior); las demás blancas con relieve.
class _Opcion extends StatefulWidget {
  final String etiqueta;
  final IconData? icono;
  final bool elegida;
  final VoidCallback onTap;
  const _Opcion(
      {required this.etiqueta, required this.icono, required this.elegida, required this.onTap});

  @override
  State<_Opcion> createState() => _OpcionState();
}

class _OpcionState extends State<_Opcion> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.elegida;
    final color = e ? Colors.white : AppColors.primario;
    const radio = BorderRadius.all(Radius.circular(12));
    return Padding(
      // Lugar para la sombra (el scroll la recortaría).
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: radio,
            gradient: e
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E8B57), AppColors.primario])
                : null,
            color: e ? null : Colors.white,
            border: Border.all(
                color: e
                    ? Colors.white.withValues(alpha: 0.25)
                    : (_encima ? AppColors.primario.withValues(alpha: 0.5) : const Color(0xFFD5DDE3))),
            boxShadow: [
              BoxShadow(
                color: e
                    ? AppColors.primario.withValues(alpha: _encima ? 0.5 : 0.35)
                    : Colors.black.withValues(alpha: _encima ? 0.12 : 0.06),
                blurRadius: e ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radio,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.icono != null) ...[
                    Icon(widget.icono, size: 17, color: color),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.etiqueta,
                      style: TextStyle(
                          color: e ? Colors.white : Colors.black87,
                          fontWeight: e ? FontWeight.w600 : FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícono de cada almacén (por nombre: los almacenes son filas de la base).
IconData iconoAlmacen(String nombre) {
  final n = nombre.toLowerCase();
  if (n.contains('jarabe')) return Icons.water_drop_outlined;
  if (n.contains('soplado')) return Icons.local_drink_outlined;
  if (n.contains('soda')) return Icons.science_outlined;
  return Icons.warehouse_outlined;
}
