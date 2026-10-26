import 'package:flutter/material.dart';

/// Marca un registro hecho sin internet que todavía no llegó al servidor
/// (id provisorio, ver `filasSinSubir`).
class ChipSinSubir extends StatelessWidget {
  const ChipSinSubir({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Se hizo sin internet y está guardado en esta compu. '
            'Se sube solo cuando vuelva la conexión.',
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: const Color(0xFFB45309).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 13, color: Color(0xFFB45309)),
            SizedBox(width: 4),
            Text('Sin subir',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
          ]),
        ),
      );
}
