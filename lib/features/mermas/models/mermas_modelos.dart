// Modelos del módulo de Mermas.

class ErrorNegocioMermas implements Exception {
  final String mensaje;
  const ErrorNegocioMermas(this.mensaje);
  @override
  String toString() => mensaje;
}

class Sabor {
  final int id;
  final String nombre;
  const Sabor({required this.id, required this.nombre});
  factory Sabor.fromMap(Map<String, dynamic> m) =>
      Sabor(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

class Presentacion {
  final int id;
  final String nombre;
  const Presentacion({required this.id, required this.nombre});
  factory Presentacion.fromMap(Map<String, dynamic> m) =>
      Presentacion(id: (m['id'] as num).toInt(), nombre: m['nombre'] as String);
}

/// Las tres áreas que registran acá (Soplado/Llenadora/Codificación ya
/// tienen su propia merma dentro de sus corridas). "Vidrio" es la línea de
/// envasado en vidrio, sin rol propio en el organigrama: la carga el Jefe
/// de Producción o el Gerente hasta que se confirme quién debe hacerlo.
enum AreaMerma {
  jarabes('jarabes', 'Jarabes', [
    Causa('menor_volumen', 'Menor volumen del esperado'),
    Causa('diferencia_peso_insumos', 'Diferencia de peso de insumos'),
  ]),
  calidad('calidad', 'Calidad', [
    Causa('exceso_agua', 'Exceso de agua (Brix o volumen fuera de rango)'),
  ]),
  vidrio('vidrio', 'Vidrio', [
    Causa('botellas_quebradas', 'Botellas quebradas'),
    Causa('de_racion', 'De ración'),
    Causa('descarte_suciedad', 'Descarte por suciedad'),
    Causa('tapas_usadas', 'Tapas usadas'),
  ]);

  final String id;
  final String etiqueta;
  final List<Causa> causas;
  const AreaMerma(this.id, this.etiqueta, this.causas);
  static AreaMerma desde(String id) => values.firstWhere((a) => a.id == id);
}

class Causa {
  final String id;
  final String etiqueta;
  const Causa(this.id, this.etiqueta);
}

/// Una fila del consolidado (`mermas_consolidado`): un evento de merma, de
/// cualquier área, ya con el porcentaje sobre lo producido y la alerta.
class EventoMerma {
  final String origen;
  final int id;
  final DateTime fecha;
  final String area;
  final String sabor;
  final String? presentacion;
  final double totalMerma;
  final double? producido;
  final double? porcentaje;
  final bool alerta;
  final String? motivo;

  const EventoMerma({
    required this.origen,
    required this.id,
    required this.fecha,
    required this.area,
    required this.sabor,
    this.presentacion,
    required this.totalMerma,
    this.producido,
    this.porcentaje,
    this.alerta = false,
    this.motivo,
  });

  factory EventoMerma.fromMap(Map<String, dynamic> m) => EventoMerma(
        origen: m['origen'] as String,
        id: (m['id'] as num).toInt(),
        fecha: DateTime.parse(m['fecha'] as String),
        area: m['area'] as String,
        sabor: m['sabor'] as String,
        presentacion: m['presentacion'] as String?,
        totalMerma: (m['total_merma'] as num).toDouble(),
        producido: (m['producido'] as num?)?.toDouble(),
        porcentaje: (m['porcentaje'] as num?)?.toDouble(),
        alerta: m['alerta'] as bool? ?? false,
        motivo: m['motivo'] as String?,
      );
}
