// Modelos de Permisos por rol (Configuración). Espejo de `app_modulos` y
// `permisos_rol` (schema_v17) — quien realmente autoriza sigue siendo el
// servidor (RLS con `tiene_permiso`); esta pantalla solo edita esa tabla.

class ModuloApp {
  final String id;
  final String nombre;
  const ModuloApp({required this.id, required this.nombre});
  factory ModuloApp.fromMap(Map<String, dynamic> m) =>
      ModuloApp(id: m['id'] as String, nombre: m['nombre'] as String);
}

/// Las 5 acciones posibles (`permisos_rol.accion`). No todos los módulos
/// usan las 5 — se muestran todas igual, no cuesta nada tener una vacía.
const accionesPosibles = ['ver', 'crear', 'editar', 'eliminar', 'aprobar'];

const _etiquetasAccion = {
  'ver': 'Ver',
  'crear': 'Crear',
  'editar': 'Editar',
  'eliminar': 'Eliminar',
  'aprobar': 'Aprobar',
};
String etiquetaAccion(String accion) => _etiquetasAccion[accion] ?? accion;
