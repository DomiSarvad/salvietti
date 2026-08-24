import 'package:flutter/material.dart';

/// Roles del sistema — deben coincidir EXACTO con el check constraint
/// de la tabla `usuarios` en Supabase (rol) y con las políticas RLS.
class Rol {
  static const almacen = 'almacen'; // control total
  static const gerente = 'gerente'; // solo observación + alta de usuarios
  static const jefeProduccion = 'jefe_produccion'; // planifica producción
  static const jarabes = 'jarabes'; // restringido a su área

  static const todos = [almacen, gerente, jefeProduccion, jarabes];

  static String etiqueta(String rol) {
    switch (rol) {
      case almacen:
        return 'Encargado de Almacén';
      case gerente:
        return 'Gerente';
      case jefeProduccion:
        return 'Jefe de Producción';
      case jarabes:
        return 'Encargado de Jarabes';
      default:
        return rol;
    }
  }
}

/// Estado semafórico de un ítem según sus días de existencia estimados.
enum EstadoStock { optimo, bajo, critico }

class SemaforoStock {
  static EstadoStock evaluar(double diasExistencia) {
    if (diasExistencia <= 3) return EstadoStock.critico;
    if (diasExistencia <= 7) return EstadoStock.bajo;
    return EstadoStock.optimo;
  }

  static Color color(EstadoStock estado) {
    switch (estado) {
      case EstadoStock.critico:
        return const Color(0xFFDC2626);
      case EstadoStock.bajo:
        return const Color(0xFFD97706);
      case EstadoStock.optimo:
        return const Color(0xFF16A34A);
    }
  }

  static String etiqueta(EstadoStock estado) {
    switch (estado) {
      case EstadoStock.critico:
        return 'CRÍTICO';
      case EstadoStock.bajo:
        return 'BAJO';
      case EstadoStock.optimo:
        return 'ÓPTIMO';
    }
  }
}

/// Nombres de "cajas" (boxes) de Hive para el almacenamiento offline.
class HiveBoxes {
  static const tapas = 'box_tapas';
  static const preformas = 'box_preformas';
  static const materiaPrima = 'box_materia_prima';
  static const colaMovimientos = 'box_cola_movimientos'; // pendientes de subir
  static const sesion = 'box_sesion';
}

class AppColors {
  static const primario = Color(0xFF0F3D6B); // azul corporativo Salvietti
  static const secundario = Color(0xFF16A34A); // verde operativo
  static const fondo = Color(0xFFF5F7FA);
}
