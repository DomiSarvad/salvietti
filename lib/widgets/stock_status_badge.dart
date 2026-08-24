import 'package:flutter/material.dart';
import '../core/constants.dart';

class StockStatusBadge extends StatelessWidget {
  final double diasExistencia;
  const StockStatusBadge({super.key, required this.diasExistencia});

  @override
  Widget build(BuildContext context) {
    final estado = SemaforoStock.evaluar(diasExistencia);
    final color = SemaforoStock.color(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            SemaforoStock.etiqueta(estado),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
