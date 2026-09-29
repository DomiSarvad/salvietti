/// Datos personales de un empleado (tabla `datos_empleado`). Celular, carnet,
/// dirección y fecha de nacimiento son los obligatorios: sin ellos el
/// empleado no puede pasar de la pantalla "Completá tus datos".
class DatosEmpleado {
  final String? celular;
  final String? carnet;
  final String? direccion;
  final DateTime? fechaNacimiento;
  final DateTime? fechaIngreso; // la define el Gerente

  const DatosEmpleado({
    this.celular,
    this.carnet,
    this.direccion,
    this.fechaNacimiento,
    this.fechaIngreso,
  });

  static bool _lleno(String? t) => t != null && t.trim().isNotEmpty;

  /// Tiene todos los datos obligatorios.
  bool get completo =>
      _lleno(celular) && _lleno(carnet) && _lleno(direccion) && fechaNacimiento != null;

  factory DatosEmpleado.fromMap(Map<String, dynamic> m) => DatosEmpleado(
        celular: m['celular'],
        carnet: m['carnet'],
        direccion: m['direccion'],
        fechaNacimiento: m['fecha_nacimiento'] != null
            ? DateTime.tryParse(m['fecha_nacimiento'])
            : null,
        fechaIngreso:
            m['fecha_ingreso'] != null ? DateTime.tryParse(m['fecha_ingreso']) : null,
      );

  static String? _fechaIso(DateTime? d) => d?.toIso8601String().substring(0, 10);

  Map<String, dynamic> toMap({bool incluirFechaIngreso = false}) => {
        'celular': _lleno(celular) ? celular!.trim() : null,
        'carnet': _lleno(carnet) ? carnet!.trim() : null,
        'direccion': _lleno(direccion) ? direccion!.trim() : null,
        'fecha_nacimiento': _fechaIso(fechaNacimiento),
        if (incluirFechaIngreso) 'fecha_ingreso': _fechaIso(fechaIngreso),
      };

  /// Validación de formato. Con [obligatorios] = true además exige los cuatro
  /// datos (lo que pide el empleado al completar); el Gerente puede guardar
  /// datos parciales y solo se le valida el formato de lo que escriba.
  String? validar({required bool obligatorios}) {
    final cel = celular?.trim() ?? '';
    final ci = carnet?.trim() ?? '';
    final dir = direccion?.trim() ?? '';

    if (cel.isEmpty) {
      if (obligatorios) return 'Ingresá tu número de celular.';
    } else {
      final digitos = cel.replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^\+?[0-9\s\-()]+$').hasMatch(cel) ||
          digitos.length < 7 ||
          digitos.length > 15) {
        return 'El celular no es válido (solo números, entre 7 y 15 dígitos).';
      }
    }

    if (ci.isEmpty) {
      if (obligatorios) return 'Ingresá tu carnet de identidad.';
    } else if (!RegExp(r'^[A-Za-z0-9\-\s]{5,20}$').hasMatch(ci)) {
      return 'El carnet no es válido (entre 5 y 20 letras o números).';
    }

    if (dir.isEmpty) {
      if (obligatorios) return 'Ingresá tu dirección.';
    } else if (dir.length < 5) {
      return 'La dirección es demasiado corta.';
    } else if (dir.length > 200) {
      return 'La dirección es demasiado larga.';
    }

    final fn = fechaNacimiento;
    if (fn == null) {
      if (obligatorios) return 'Elegí tu fecha de nacimiento.';
    } else {
      final hoy = DateTime.now();
      var edad = hoy.year - fn.year;
      if (hoy.month < fn.month || (hoy.month == fn.month && hoy.day < fn.day)) edad--;
      if (edad < 16 || fn.year < 1930) {
        return 'La fecha de nacimiento no es válida (tiene que ser mayor de 16 años).';
      }
    }
    return null;
  }
}
