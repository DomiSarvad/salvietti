import 'dart:math' as math;

import '../models/insumo_model.dart';

enum InventarioEstado { critico, advertencia, seguro }

class InventarioLogicService {
  static double consumoDiarioPromedio({
    required double totalConsumido,
    required int dias,
  }) {
    if (dias <= 0) {
      return 0;
    }
    return totalConsumido / dias;
  }

  static double autonomiaInventario({
    required double stockActual,
    required double cdp,
  }) {
    if (cdp <= 0) {
      return double.infinity;
    }
    return stockActual / cdp;
  }

  static double puntoReposicion({
    required double cdp,
    required int leadTime,
    required double stockSeguridad,
  }) {
    return (cdp * leadTime) + stockSeguridad;
  }

  static double stockSeguridad({
    required double consumoHabitual,
    required double porcentaje,
  }) {
    return consumoHabitual * porcentaje;
  }

  static InventarioEstado evaluarEstadoInsumo({
    required InsumoModel insumo,
    required int leadTime,
    required double porcentajeStockSeguridad,
  }) {
    final cdp = consumoDiarioPromedio(
      totalConsumido: insumo.consumoPromedio30,
      dias: 30,
    );

    final diasRestantes = autonomiaInventario(
      stockActual: insumo.stockActual,
      cdp: cdp,
    );

    final pr = puntoReposicion(
      cdp: cdp,
      leadTime: leadTime,
      stockSeguridad: stockSeguridad(
        consumoHabitual: cdp,
        porcentaje: porcentajeStockSeguridad,
      ),
    );

    final vencimientoEnDias = insumo.diasHastaVencimiento;

    final critico = diasRestantes < 3 || vencimientoEnDias < 7;
    final advertencia =
        (diasRestantes >= 3 && diasRestantes <= 7) ||
        (insumo.stockActual <= pr && insumo.stockActual > 0);

    if (critico) {
      return InventarioEstado.critico;
    }
    if (advertencia) {
      return InventarioEstado.advertencia;
    }
    return InventarioEstado.seguro;
  }

  static String textoAlerta({
    required InsumoModel insumo,
    required int leadTime,
    required double porcentajeStockSeguridad,
  }) {
    final cdp = consumoDiarioPromedio(
      totalConsumido: insumo.consumoPromedio30,
      dias: 30,
    );

    final diasRestantes = autonomiaInventario(
      stockActual: insumo.stockActual,
      cdp: cdp,
    );

    final pr = puntoReposicion(
      cdp: cdp,
      leadTime: leadTime,
      stockSeguridad: stockSeguridad(
        consumoHabitual: cdp,
        porcentaje: porcentajeStockSeguridad,
      ),
    );

    final estado = evaluarEstadoInsumo(
      insumo: insumo,
      leadTime: leadTime,
      porcentajeStockSeguridad: porcentajeStockSeguridad,
    );

    switch (estado) {
      case InventarioEstado.critico:
        final dias = diasRestantes.isFinite ? diasRestantes : 0;
        return 'ALERTA URGENTE: El insumo ${insumo.nombre} se agotará en ${dias.toStringAsFixed(1)} días. Solicitar reabastecimiento inmediatamente. PR estimado: ${pr.toStringAsFixed(2)}';
      case InventarioEstado.advertencia:
        return 'PRECAUCIÓN: ${insumo.nombre} está en punto de retorno. Stock actual ${insumo.stockActual.toStringAsFixed(2)}. Revisión de compra recomendada.';
      case InventarioEstado.seguro:
        return '${insumo.nombre} en operación segura. Stock suficiente para ${diasRestantes.isFinite ? diasRestantes.toStringAsFixed(1) : 'varios'} días.';
    }
  }

  static Map<String, dynamic> calcularPlanProduccion({
    required int unidadesObjetivo,
    required double rendimientoPorUnidad,
    required double desperdicio,
  }) {
    final base = unidadesObjetivo * rendimientoPorUnidad;
    final conDesperdicio = base * (1 + desperdicio);

    return {
      'unidades_objetivo': unidadesObjetivo,
      'rendimiento_por_unidad': rendimientoPorUnidad,
      'desperdicio': desperdicio,
      'cantidad_total_requerida': conDesperdicio,
      'cantidad_base_sin_desperdicio': base,
      'margen_extra': conDesperdicio - base,
    };
  }

  static Map<String, dynamic> calcularNecesidadesPorProducto({
    required Map<String, dynamic> plan,
    required Map<String, double> recetaPorInsumo,
  }) {
    final resultado = <String, dynamic>{};
    final cantidadBase = (plan['cantidad_total_requerida'] as num).toDouble();

    for (final entry in recetaPorInsumo.entries) {
      final necesidad = cantidadBase * entry.value;
      resultado[entry.key] = necesidad;
    }

    return resultado;
  }

  static double redondearCantidad(double valor, {int decimales = 2}) {
    final factor = math.pow(10, decimales).toDouble();
    return (valor * factor).round() / factor;
  }
}
