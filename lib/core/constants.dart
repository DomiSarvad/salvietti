import 'package:flutter/material.dart';

/// Roles del sistema — deben coincidir EXACTO con el check constraint
/// de la tabla `usuarios` en Supabase (rol) y con las políticas RLS.
///
/// Organigrama: Gerente General → Producción → (Almacén, Jarabes, Soplado,
/// Llenadora, Codificación, Registro de Salidas, Control de Calidad).
/// Los cargos nuevos arrancan en solo lectura; sus permisos propios se
/// agregan al implementar el módulo de cada área.
class Rol {
  static const almacen = 'almacen'; // control total
  static const gerente = 'gerente'; // Gerente General: observación + usuarios
  static const jefeProduccion = 'jefe_produccion'; // planifica producción
  static const jarabes = 'jarabes'; // Jefe de Jarabes: restringido a su área
  static const ayudanteJarabes = 'ayudante_jarabes'; // mismo alcance que Jarabes
  static const controlCalidad = 'control_calidad';
  static const soplado = 'soplado';
  static const codificacion = 'codificacion';
  static const llenadora = 'llenadora';
  static const registroSalidas = 'registro_salidas';
  static const sodaCaustica = 'soda_caustica';

  /// Roles que en el menú ven INFORMES en vez de las pantallas de trabajo de
  /// cada área (Almacenes, Soplado, Jarabes…): el Gerente no opera, mira
  /// resultados. Es solo presentación — los datos los sigue protegiendo el
  /// servidor con sus permisos —, y esas pantallas siguen abriéndose desde la
  /// campana cuando hace falta (ej. un pedido de compra por aprobar).
  static const soloInformes = {gerente};

  /// Roles que no ven lo operativo de Almacén (Recepciones, Pedidos de las
  /// áreas, Pedidos de compra) ni el avance de Soplado en Jarabes: van directo
  /// a los resultados (Informes). Solo presentación, igual que [soloInformes]:
  /// conservan el permiso "ver" porque Informes lee esas tablas.
  static const sinOperacionAlmacen = {jefeProduccion};

  /// Ordenados por área, tal como se muestran en el selector.
  static const todos = [
    gerente,
    jefeProduccion,
    almacen,
    jarabes,
    ayudanteJarabes,
    soplado,
    llenadora,
    codificacion,
    registroSalidas,
    controlCalidad,
    sodaCaustica,
  ];

  static String etiqueta(String rol) {
    switch (rol) {
      case almacen:
        return 'Encargado de Almacén';
      case gerente:
        return 'Gerente General';
      case jefeProduccion:
        return 'Jefe de Producción';
      case jarabes:
        return 'Jefe de Jarabes';
      case ayudanteJarabes:
        return 'Ayudante de Jarabes';
      case controlCalidad:
        return 'Encargado de Control de Calidad';
      case soplado:
        return 'Encargado de Soplado';
      case codificacion:
        return 'Encargado de Codificación';
      case llenadora:
        return 'Encargado de Llenadora';
      case registroSalidas:
        return 'Encargado de Registro de Salidas';
      case sodaCaustica:
        return 'Encargado de Soda Cáustica';
      default:
        return rol;
    }
  }

  /// Área del organigrama a la que pertenece el cargo.
  static String area(String rol) {
    switch (rol) {
      case gerente:
        return 'Gerencia';
      case jefeProduccion:
        return 'Producción';
      case almacen:
        return 'Producción · Almacén';
      case jarabes:
      case ayudanteJarabes:
        return 'Producción · Jarabes';
      case soplado:
        return 'Producción · Soplado';
      case llenadora:
        return 'Producción · Llenadora';
      case codificacion:
        return 'Producción · Codificación';
      case registroSalidas:
        return 'Producción · Registro de Salidas';
      case controlCalidad:
        return 'Producción · Control de Calidad';
      case sodaCaustica:
        return 'Producción · Soda Cáustica';
      default:
        return '';
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
  // 254 es el máximo técnico (RFC 5321), pero en la práctica ningún correo
  // real se acerca a eso: 100 alcanza de sobra y evita un contador que
  // parece pedir un texto larguísimo.
  static const emailMax = 100;
}

/// Las cuatro áreas de inventario, cada una con un color y un ícono propios
/// que se repiten en el dashboard, los gráficos y la lista de inventario
/// para que se identifiquen a simple vista. Los tonos siguen la paleta de la
/// app (verde, dorado, carbón); el ámbar y el rojo quedan reservados al
/// semáforo de stock.
class AreaInventario {
  final String id; // 'tapas' | 'preformas' | 'materia_prima' | 'jarabes'
  final String etiqueta;
  final String tabla; // tabla en la base de datos
  final Color color;
  final IconData icono;
  const AreaInventario(this.id, this.etiqueta, this.tabla, this.color, this.icono);

  static const tapas = AreaInventario(
      'tapas', 'Tapas', 'tapas', Color(0xFF1B5E3A), Icons.adjust);
  static const preformas = AreaInventario('preformas', 'Preformas', 'preformas',
      Color(0xFFC99A2E), Icons.local_drink_outlined);
  static const materiaPrima = AreaInventario('materia_prima', 'Materia Prima',
      'materia_prima', Color(0xFF37474F), Icons.grain);
  static const jarabes = AreaInventario('jarabes', 'Jarabes', 'materia_prima',
      Color(0xFF43A27B), Icons.water_drop_outlined);

  static const todas = [tapas, preformas, materiaPrima, jarabes];

  static AreaInventario porId(String id) =>
      todas.firstWhere((a) => a.id == id, orElse: () => tapas);

  /// Área de un ítem según su tabla y su campo `area` (los jarabes son
  /// materia prima marcada con área "jarabes").
  static AreaInventario deItem(String tabla, String? area) {
    if (tabla == 'materia_prima') return area == 'jarabes' ? jarabes : materiaPrima;
    return porId(tabla);
  }
}

/// Nombres de "cajas" (boxes) de Hive para el almacenamiento offline.
class HiveBoxes {
  static const tapas = 'box_tapas';
  static const preformas = 'box_preformas';
  static const materiaPrima = 'box_materia_prima';
  static const colaMovimientos = 'box_cola_movimientos'; // pendientes de subir
  static const sesion = 'box_sesion';
  static const perfilPendiente = 'box_perfil_pendiente'; // foto sin subir
  static const preferencias = 'box_preferencias'; // ej. tours de ayuda ya vistos
  // Modo sin conexión de los módulos nuevos (ver ColaOffline/ClienteOffline).
  static const cacheLecturas = 'box_cache_lecturas';
  static const cacheFechas = 'box_cache_fechas'; // cuándo se guardó cada lectura (para podar)
  static const colaOffline = 'box_cola_offline';
  static const erroresOffline = 'box_errores_offline';
  static const idsTemporales = 'box_ids_temporales';
}

class AppColors {
  // Paleta de marca Salvietti: verde sobrio como color dominante (tomado
  // del logo), dorado como acento secundario. El rojo queda reservado
  // para alertas/estados críticos (ver SemaforoStock), no como color de marca.
  static const primario = Color(0xFF1B5E3A); // verde Salvietti (sobrio)
  static const secundario = Color(0xFFC99A2E); // dorado, acento de marca
  static const negro = Color(0xFF0E1512); // negro con base verde, no gris frío
  static const fondo = Color(0xFFF5F7FA);

  // Degradado verde→negro para encabezados/banners "dinámicos" (diálogos
  // de usuario/perfil, títulos destacados): mantiene los 3 colores de marca
  // (negro-verde-blanco) sin depender de una sola pantalla.
  static const gradientePrincipal =
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
    primario,
    negro,
  ]);
}
