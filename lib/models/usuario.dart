class Usuario {
  final String id;
  final String nombreCompleto;
  final String rol;
  final String? area;
  final bool activo;
  final String? avatarUrl;

  Usuario({
    required this.id,
    required this.nombreCompleto,
    required this.rol,
    this.area,
    this.activo = true,
    this.avatarUrl,
  });

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
        id: m['id'],
        nombreCompleto: m['nombre_completo'] ?? '',
        rol: m['rol'] ?? '',
        area: m['area'],
        activo: m['activo'] ?? true,
        avatarUrl: m['avatar_url'],
      );

  bool get esAlmacen => rol == 'almacen';
  bool get esGerente => rol == 'gerente';
  bool get esJefeProduccion => rol == 'jefe_produccion';
  bool get esJarabes => rol == 'jarabes';

  /// Tapas y Preformas: control exclusivo de Almacén.
  bool get puedeEditarTapasPreformas => esAlmacen;

  /// Materia Prima: Almacén (todo) o Jarabes (solo lo marcado como su área).
  bool get puedeEditarMateriaPrima => esAlmacen || esJarabes;

  /// Planificación de producción del día: exclusivo de Jefe de Producción.
  bool get puedeEditarProduccion => esJefeProduccion;

  /// Solo almacén puede eliminar (lógicamente) ítems del inventario.
  bool get puedeEliminar => esAlmacen;

  /// Solo el Gerente da de alta nuevos usuarios; el resto (incluido
  /// Almacén) únicamente puede ver la lista.
  bool get puedeCrearUsuarios => esGerente;

  /// Quiénes ven la pestaña "Usuarios" (aunque no todos puedan crear).
  bool get puedeVerUsuarios => esGerente || esAlmacen;

  /// El Gerente ya no navega el catálogo crudo de Inventario: solo
  /// estadísticas/reportes.
  bool get puedeVerInventario => !esGerente;

  /// Producción del día sí la ve todo el mundo (Gerente, Jarabes,
  /// Almacén e Ingeniero): necesitan saber qué hay que hacer aunque no
  /// puedan tocarlo. Completar tareas sigue siendo exclusivo del
  /// Ingeniero vía `puedeEditarProduccion`.
  bool get puedeVerProduccion => true;

  /// Estadísticas y Reportes las ve todo el mundo (el contenido cambia
  /// según el rol: Jarabes ve su propia área, el resto ve la planta).
  bool get puedeVerEstadisticas => true;
  bool get puedeVerReportes => true;

  /// El gerente solo observa: nunca registra movimientos ni produce.
  bool get soloLectura => esGerente;
}
