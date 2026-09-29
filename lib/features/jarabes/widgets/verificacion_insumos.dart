import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../models/jarabes_modelos.dart';

/// Lista de insumos necesarios contra lo disponible, con lo que falta
/// resaltado en rojo. Se usa antes de iniciar un preparado.
class VerificacionInsumos extends StatelessWidget {
  final List<VerificacionInsumo> items;
  const VerificacionInsumos({super.key, required this.items});

  bool get hayFaltantes => items.any((i) => !i.alcanza);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hayFaltantes ? const Color(0xFFFDECEC) : const Color(0xFFF0FAF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hayFaltantes ? const Color(0xFFEFA0A0) : const Color(0xFFB6E3C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hayFaltantes ? 'Falta insumo para esta cantidad' : 'Alcanza con el stock actual',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: hayFaltantes ? const Color(0xFFB03030) : const Color(0xFF16A34A)),
          ),
          const SizedBox(height: 6),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(i.detalle, style: const TextStyle(fontSize: 13))),
                  Text(
                    '${fmtNum(i.necesario, decimales: 3)} / ${fmtNum(i.disponible, decimales: 3)} ${i.unidad}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: i.alcanza ? Colors.black54 : const Color(0xFFDC2626)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
