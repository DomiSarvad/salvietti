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

/// Reglas de validación de contraseña, compartidas por login, alta de
/// usuarios, cambio de contraseña y recuperación.
class Validacion {
  static const passwordMin = 6;
  static const passwordMax = 10;
}

/// Nombres de "cajas" (boxes) de Hive para el almacenamiento offline.
class HiveBoxes {
  static const tapas = 'box_tapas';
  static const preformas = 'box_preformas';
  static const materiaPrima = 'box_materia_prima';
  static const colaMovimientos = 'box_cola_movimientos'; // pendientes de subir
  static const sesion = 'box_sesion';
  static const perfilPendiente = 'box_perfil_pendiente'; // foto sin subir
}

class AppColors {
  // Paleta de marca Salvietti: verde sobrio como color dominante (tomado
  // del logo), dorado como acento secundario. El rojo queda reservado
  // para alertas/estados críticos (ver SemaforoStock), no como color de marca.
  static const primario = Color(0xFF1B5E3A); // verde Salvietti (sobrio)
  static const secundario = Color(0xFFC99A2E); // dorado, acento de marca
  static const fondo = Color(0xFFF5F7FA);
}
