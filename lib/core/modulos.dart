/// Módulos del sistema y acciones posibles sobre cada uno. Los ids deben
/// coincidir con la tabla `app_modulos` de Supabase (schema_v17): la app
/// solo usa estos permisos para mostrar u ocultar; quien realmente
/// autoriza es el servidor (políticas RLS con `tiene_permiso`).
///
/// Para sumar un módulo: agregar su id acá, su fila en `app_modulos` y sus
/// filas en `permisos_rol`.
class Modulo {
  static const dashboard = 'dashboard';
  static const inventarioGeneral = 'inventario_general';
  static const inventarioJarabes = 'inventario_jarabes';
  static const inventarioSoplado = 'inventario_soplado';
  static const inventarioSodaCaustica = 'inventario_soda_caustica';
  static const recepciones = 'recepciones';
  static const entregas = 'entregas';
  static const solicitudes = 'solicitudes';
  static const aprobaciones = 'aprobaciones';
  static const planProduccion = 'plan_produccion';
  static const soplado = 'soplado';
  static const jarabesProduccion = 'jarabes_produccion';
  static const recetas = 'recetas';
  static const calidad = 'calidad';
  static const llenado = 'llenado';
  static const codificacion = 'codificacion';
  static const salidas = 'salidas';
  static const mermas = 'mermas';
  static const sodaCaustica = 'soda_caustica';
  static const informeProduccion = 'informe_produccion';
  static const historial = 'historial';
  static const usuarios = 'usuarios';
  static const permisos = 'permisos';
  static const compras = 'compras'; // pedidos de compra de Almacén (v43)

  /// Módulos que abren la pantalla de Almacenes.
  static const inventarios = [
    inventarioGeneral, inventarioJarabes, inventarioSoplado, inventarioSodaCaustica,
  ];

  /// Módulo de permisos de un almacén ('general' → 'inventario_general').
  static String inventarioDe(String almacenId) => 'inventario_$almacenId';
}

class Accion {
  static const ver = 'ver';
  static const crear = 'crear';
  static const editar = 'editar';
  static const eliminar = 'eliminar';
  static const aprobar = 'aprobar';
}
