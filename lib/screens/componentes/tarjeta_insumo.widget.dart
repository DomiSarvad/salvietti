import 'package:flutter/material.dart';

import '../../models/insumo_model.dart';

class TarjetaInsumoWidget extends StatelessWidget {
  final InsumoModel insumo;
  final bool canDelete;
  final VoidCallback? onDelete;

  const TarjetaInsumoWidget({
    super.key,
    required this.insumo,
    this.canDelete = false,
    this.onDelete,
  });

  Color get borderColor {
    if (insumo.nivelStock == StockNivel.critico) {
      return Colors.red.shade700;
    }
    if (insumo.nivelStock == StockNivel.observacion) {
      return Colors.orange.shade700;
    }
    return Colors.green.shade900;
  }

  double get borderWidth {
    if (insumo.nivelStock == StockNivel.critico) {
      return 3.2;
    }
    if (insumo.nivelStock == StockNivel.observacion) {
      return 2.4;
    }
    return 1.8;
  }

  String get estadoLabel {
    if (insumo.nivelStock == StockNivel.critico) {
      return 'CRÍTICO';
    }
    if (insumo.nivelStock == StockNivel.observacion) {
      return 'OBSERVACIÓN';
    }
    return 'OPERATIVO';
  }

  String get estadoDetalle {
    if (insumo.nivelStock == StockNivel.critico) {
      return insumo.diasHastaVencimiento < 7
          ? 'Lote venciendo pronto'
          : 'Stock crítico';
    }
    if (insumo.nivelStock == StockNivel.observacion) {
      return 'Revisar consumo';
    }
    return 'Stock saludable';
  }

  String get indicadorRotacion {
    if (insumo.rotacionLenta) {
      return 'Rotación lenta';
    }
    return '${insumo.diasRestantesStock.toStringAsFixed(1)} DÍAS';
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = insumo.nivelStock == StockNivel.critico;
    final isObservation = insumo.nivelStock == StockNivel.observacion;

    return Card(
      elevation: 2,
      color: isCritical
          ? Colors.red.shade50
          : isObservation
          ? Colors.orange.shade50
          : Colors.green.shade50,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    insumo.nombre,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canDelete)
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade700,
                    ),
                    tooltip: 'Borrado lógico',
                    visualDensity: VisualDensity.compact,
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: borderColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      estadoLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: borderColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Stock actual: ${insumo.stockActual.toStringAsFixed(0)} ${insumo.unidadMedida}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Lote: ${insumo.numeroLote}'),
            const SizedBox(height: 8),
            if (insumo.fechaVencimiento != null)
              Text(
                'Vencimiento: ${insumo.fechaVencimiento!.day}/${insumo.fechaVencimiento!.month}/${insumo.fechaVencimiento!.year}',
              ),
            const SizedBox(height: 12),
            Text(
              indicadorRotacion,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                estadoDetalle,
                style: TextStyle(
                  fontSize: 12,
                  color: borderColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (insumo.rotacionLenta)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Insumo sin movimientos en 10 días',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
