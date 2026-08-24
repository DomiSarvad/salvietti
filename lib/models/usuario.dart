class Usuario {
  final String id;
  final String nombreCompleto;
  final String rol;
  final String? area;
  final bool activo;

  Usuario({
    required this.id,
    required this.nombreCompleto,
    required this.rol,
    this.area,
    this.activo = true,
  });

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
        id: m['id'],
        nombreCompleto: m['nombre_completo'] ?? '',
        rol: m['rol'] ?? '',
        area: m['area'],
        activo: m['activo'] ?? true,
      );

  bool get esAlmacen => rol == 'almacen';
  bool get esGerente => rol == 'gerente';
  bool get esJefeProduccion => rol == 'jefe_produccion';
  bool get esJarabes => rol == 'jarabes';

  /// Control total del catálogo y fórmulas.
  bool get puedeEditarCatalogo => esAlmacen || esJefeProduccion;

  /// Solo almacén puede eliminar (lógicamente) y editar usuarios.
  bool get puedeEliminar => esAlmacen;

  /// Almacén y gerente pueden dar de alta nuevos usuarios.
  bool get puedeCrearUsuarios => esAlmacen || esGerente;

  /// El gerente solo observa: nunca registra movimientos ni produce.
  bool get soloLectura => esGerente;
}
