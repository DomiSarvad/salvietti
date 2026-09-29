import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Círculo de color con el ícono del área: la "marca" visual que identifica
/// a cada área de inventario en el dashboard, los gráficos y la lista.
class AreaIcono extends StatelessWidget {
  final AreaInventario area;
  final double tamano;
  const AreaIcono(this.area, {super.key, this.tamano = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(color: area.color, shape: BoxShape.circle),
      child: Icon(area.icono, size: tamano * 0.55, color: Colors.white),
    );
  }
}

/// Leyenda "color = área" para acompañar a los gráficos y al dashboard.
class LeyendaAreas extends StatelessWidget {
  final List<AreaInventario> areas;
  const LeyendaAreas({super.key, required this.areas});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final a in areas)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AreaIcono(a, tamano: 22),
              const SizedBox(width: 6),
              Text(a.etiqueta, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }
}
