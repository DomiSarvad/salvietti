import '../core/modulos.dart';

class Usuario {
  final String id;
  final String nombreCompleto;
  final String rol;
  final String? area;
  final bool activo;
  final String? avatarUrl;

  /// Permisos del rol como "modulo:accion" (ver `Modulo` y `Accion`). Null =
  /// todavía no se cargaron o no están disponibles: se usan las reglas
  /// anteriores por rol.
  final Set<String>? permisos;

  Usuario({
    required this.id,
    required this.nombreCompleto,
    required this.rol,
    this.area,
    this.activo = true,
    this.avatarUrl,
    this.permisos,
  });

  Usuario conPermisos(Set<String>? permisos) => Usuario(
        id: id,
        nombreCompleto: nombreCompleto,
        rol: rol,
        area: area,
        activo: activo,
        avatarUrl: avatarUrl,
        permisos: permisos,
      );

  /// ¿Puede este rol hacer [accion] en [modulo]? Sin permisos cargados usa
  /// [reglaAnterior], la regla que existía antes del modelo por módulos.
  bool puede(String modulo, String accion, {required bool reglaAnterior}) =>
      permisos == null ? reglaAnterior : permisos!.contains('$modulo:$accion');

  bool puedeVerModulo(String modulo) =>
      puede(modulo, Accion.ver, reglaAnterior: false);

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
  bool get esJefeJarabes => rol == 'jarabes';

  /// El Ayudante de Jarabes tiene el mismo alcance que el Jefe de Jarabes
  /// sobre el inventario de su área.
  bool get esJarabes => rol == 'jarabes' || rol == 'ayudante_jarabes';

  /// Quién controla cada área de inventario (editar ítems, registrar
  /// movimientos, eliminar): Tapas, Preformas y Materia Prima son de
  /// Almacén; Jarabes es EXCLUSIVA del área de Jarabes — Almacén no puede
  /// modificarla.
  bool puedeEditarArea(String areaId) => areaId == 'jarabes'
      ? puede(Modulo.inventarioJarabes, Accion.editar, reglaAnterior: esJarabes)
      : puede(Modulo.inventarioGeneral, Accion.editar, reglaAnterior: esAlmacen);

  /// Planificación de producción del día.
  bool get puedeEditarProduccion =>
      puede(Modulo.planProduccion, Accion.editar, reglaAnterior: esJefeProduccion);

  /// Alta de nuevos usuarios; los demás únicamente pueden ver la lista.
  bool get puedeCrearUsuarios =>
      puede(Modulo.usuarios, Accion.crear, reglaAnterior: esGerente);

  /// Quiénes ven la pestaña "Usuarios" (aunque no todos puedan crear).
  bool get puedeVerUsuarios =>
      puede(Modulo.usuarios, Accion.ver, reglaAnterior: esGerente || esAlmacen);

  /// Quiénes ven la Bitácora.
  bool get puedeVerHistorial =>
      puede(Modulo.historial, Accion.ver, reglaAnterior: esAlmacen || esGerente);

  /// Ve Inventario quien pueda ver algún almacén. Sin permisos cargados se
  /// mantiene la regla anterior (todos menos el Gerente).
  bool get puedeVerInventario => permisos == null
      ? !esGerente
      : Modulo.inventarios.any(puedeVerModulo);

  /// Producción del día sí la ve todo el mundo (Gerente, Jarabes,
  /// Almacén e Ingeniero): necesitan saber qué hay que hacer aunque no
  /// puedan tocarlo. Completar tareas sigue siendo exclusivo del
  /// Ingeniero vía `puedeEditarProduccion`.
  bool get puedeVerProduccion =>
      puede(Modulo.planProduccion, Accion.ver, reglaAnterior: true);

  /// El gerente solo observa: nunca registra movimientos ni produce.
  bool get soloLectura => esGerente;
}
