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
            child: Builder(builder: (_) {
              final elegida = o == seleccionada;
              final ic = icono?.call(o);
              return ChoiceChip(
                avatar: ic == null
                    ? null
                    : Icon(ic, size: 16, color: elegida ? Colors.white : AppColors.primario),
                showCheckmark: false,
                label: Text(etiqueta(o)),
                selected: elegida,
                selectedColor: AppColors.primario,
                labelStyle: TextStyle(color: elegida ? Colors.white : Colors.black87),
                onSelected: (_) => onElegir(o),
              );
            }),
          ),
      ]),
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
