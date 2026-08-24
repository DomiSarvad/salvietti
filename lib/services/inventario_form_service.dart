import '../models/insumo_model.dart';
import 'inventario_logic_service.dart';

class InventarioFormService {
  static String generarCodigo({
    required String prefijo,
    required int secuencia,
  }) {
    return '$prefijo-${secuencia.toString().padLeft(3, '0')}';
  }

  static String normalizarTexto(String valor) {
    return valor.trim();
  }

  static bool validarFormulario({
    required String nombre,
    required double cantidad,
    required String unidad,
  }) {
    return nombre.trim().isNotEmpty && cantidad > 0 && unidad.trim().isNotEmpty;
  }

  static Map<String, dynamic> evaluarStockParaFormulario({
    required InsumoModel insumo,
    required double cantidadSolicitada,
    required int leadTime,
    required double porcentajeSeguridad,
  }) {
    final cdp = InventarioLogicService.consumoDiarioPromedio(
      totalConsumido: insumo.consumoPromedio30,
      dias: 30,
    );
    final diasRestantes = InventarioLogicService.autonomiaInventario(
      stockActual: insumo.stockActual,
      cdp: cdp,
    );
    final pr = InventarioLogicService.puntoReposicion(
      cdp: cdp,
      leadTime: leadTime,
      stockSeguridad: InventarioLogicService.stockSeguridad(
        consumoHabitual: cdp,
        porcentaje: porcentajeSeguridad,
      ),
    );

    final hayStock = cantidadSolicitada <= insumo.stockActual;

    return {
      'permitido': hayStock,
      'dias_restantes': diasRestantes,
      'punto_reposicion': pr,
      'estado': InventarioLogicService.evaluarEstadoInsumo(
        insumo: insumo,
        leadTime: leadTime,
        porcentajeStockSeguridad: porcentajeSeguridad,
      ),
      'mensaje': hayStock
          ? 'Stock suficiente para continuar'
          : 'Stock insuficiente para la operación',
    };
  }
}
