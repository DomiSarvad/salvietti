import 'package:flutter/material.dart';

class GraficoConsumoWidget extends StatelessWidget {
  final List<double> valores;

  const GraficoConsumoWidget({super.key, required this.valores});

  @override
  Widget build(BuildContext context) {
    final maxValue =
        valores.isNotEmpty ? valores.reduce((a, b) => a > b ? a : b) : 1.0;
    final dias = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONSUMO SEMANAL (KL)',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: valores.asMap().entries.map((entry) {
              final index = entry.key;
              final value = entry.value;
              final heightFactor = maxValue > 0 ? (value / maxValue) : 0.0;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 160 * heightFactor + 12,
                      width: 18,
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(dias[index],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
