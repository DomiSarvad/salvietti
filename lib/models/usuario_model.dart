class UsuarioModel {
  final String id;
  final String nombre;
  final String email;
  final String rol;
  final bool activo;
  final String? fotoUrl;
  final String? telefono;

  UsuarioModel({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activo,
    this.fotoUrl,
    this.telefono,
  });

  factory UsuarioModel.fromMap(Map<String, dynamic> map) {
    return UsuarioModel(
      id: map['id']?.toString() ?? '',
      nombre: map['nombre']?.toString() ?? 'Usuario',
      email: map['email']?.toString() ?? '',
      rol: map['rol']?.toString() ?? 'Encargado de Almacén',
      activo: map['activo'] == null
          ? true
          : map['activo'] == true || map['activo'] == 'true',
      fotoUrl: map['foto_url']?.toString(),
      telefono: map['telefono']?.toString(),
    );
  }

  UsuarioModel copyWith({
    String? id,
    String? nombre,
    String? email,
    String? rol,
    bool? activo,
    String? fotoUrl,
    String? telefono,
  }) {
    return UsuarioModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      rol: rol ?? this.rol,
      activo: activo ?? this.activo,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      telefono: telefono ?? this.telefono,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'email': email,
      'rol': rol,
      'activo': activo,
      'foto_url': fotoUrl,
      'telefono': telefono,
    };
  }
}
