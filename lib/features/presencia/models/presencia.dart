/// El último "sigo acá" de un usuario (tabla `app_presencia`, v42).
class PresenciaUsuario {
  final String usuarioId;
  final String rol;
  final String nombre;
  final DateTime ultimaSenal;
  final int pendientes;

  /// false = cerró sesión a propósito (no es un corte de internet).
  final bool activa;

  /// Calculado con el reloj del SERVIDOR (ver `presencia_listar`): el reloj
  /// de cada compu puede estar corrido varios minutos.
  final int segundosSinSenal;

  const PresenciaUsuario({
    required this.usuarioId,
    required this.rol,
    required this.nombre,
    required this.ultimaSenal,
    required this.pendientes,
    required this.activa,
    required this.segundosSinSenal,
  });

  factory PresenciaUsuario.fromMap(Map<String, dynamic> m) => PresenciaUsuario(
        usuarioId: m['usuario_id'] as String,
        rol: m['rol'] as String,
        nombre: (m['nombre'] as String?) ?? '',
        ultimaSenal: DateTime.parse(m['ultima_senal'] as String).toLocal(),
        pendientes: (m['pendientes'] as num?)?.toInt() ?? 0,
        activa: m['activa'] as bool? ?? true,
        segundosSinSenal: (m['segundos_sin_senal'] as num?)?.toInt() ?? 0,
      );
}

enum TipoAvisoArea {
  /// Dejó de dar señal con la sesión abierta: probablemente sin internet, y
  /// lo que registre queda en su compu hasta que vuelva la conexión.
  sinSenal,

  /// Está conectado pero todavía tiene registros hechos sin internet por subir.
  pendientes,
}

/// Lo que se le muestra a otra área: "Soplado sin señal desde las 10:32".
class AvisoArea {
  final String rol;
  final String nombre;
  final TipoAvisoArea tipo;
  final DateTime ultimaSenal;
  final int pendientes;

  const AvisoArea({
    required this.rol,
    required this.nombre,
    required this.tipo,
    required this.ultimaSenal,
    required this.pendientes,
  });
}
