// Modelos de Informes por área (para el Gerente): un período (semana o mes),
// KPIs, series para el gráfico de barras y una tabla de detalle. Todo
// independiente de la UI y del formato de exportación (PDF/Excel).

enum PeriodoInforme {
  semana('Semanal'),
  mes('Mensual');

  final String etiqueta;
  const PeriodoInforme(this.etiqueta);
}

enum AreaInforme {
  general('General'),
  jarabes('Jarabes'),
  soplado('Soplado'),
  llenadora('Llenadora'),
  codificacion('Codificación'),
  calidad('Control de Calidad'),
  produccion('Producción terminada'),
  mermas('Mermas'),
  almacen('Almacén'),
  soda('Soda Cáustica');

  final String titulo;
  const AreaInforme(this.titulo);
}

/// Un período concreto y cómo se parte para el gráfico: la semana en días
/// (lun…dom), el mes en semanas (Sem 1…Sem 5). [hasta] es exclusivo.
class RangoInforme {
  final PeriodoInforme periodo;
  final DateTime desde;
  final DateTime hasta;
  final List<DateTime> inicios; // inicio de cada barra
  final List<String> etiquetas; // texto de cada barra

  const RangoInforme._(this.periodo, this.desde, this.hasta, this.inicios, this.etiquetas);

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// El período que contiene a [referencia].
  factory RangoInforme.de(PeriodoInforme p, DateTime referencia) {
    final d = DateTime(referencia.year, referencia.month, referencia.day);
    if (p == PeriodoInforme.semana) {
      final lunes = d.subtract(Duration(days: d.weekday - 1));
      final inicios = [for (var i = 0; i < 7; i++) DateTime(lunes.year, lunes.month, lunes.day + i)];
      return RangoInforme._(p, lunes, DateTime(lunes.year, lunes.month, lunes.day + 7), inicios,
          [for (var i = 0; i < 7; i++) '${_dias[i]} ${inicios[i].day}']);
    }
    final desde = DateTime(d.year, d.month, 1);
    final hasta = DateTime(d.year, d.month + 1, 1);
    final inicios = <DateTime>[];
    for (var dia = desde; dia.isBefore(hasta); dia = DateTime(dia.year, dia.month, dia.day + 7)) {
      inicios.add(dia);
    }
    return RangoInforme._(p, desde, hasta, inicios,
        [for (var i = 0; i < inicios.length; i++) 'Sem ${i + 1}']);
  }

  RangoInforme anterior() => RangoInforme.de(
      periodo, periodo == PeriodoInforme.semana ? desde.subtract(const Duration(days: 1)) : DateTime(desde.year, desde.month - 1, 1));
  RangoInforme siguiente() => RangoInforme.de(periodo, hasta);

  /// Índice de la barra a la que pertenece [fecha], o null si cae afuera.
  int? indiceDe(DateTime fecha) {
    if (fecha.isBefore(desde) || !fecha.isBefore(hasta)) return null;
    for (var i = inicios.length - 1; i >= 0; i--) {
      if (!fecha.isBefore(inicios[i])) return i;
    }
    return null;
  }

  String get titulo {
    String f(DateTime x) => '${x.day}/${x.month}/${x.year}';
    if (periodo == PeriodoInforme.semana) {
      return 'Semana del ${f(desde)} al ${f(hasta.subtract(const Duration(days: 1)))}';
    }
    return '${_meses[desde.month - 1][0].toUpperCase()}${_meses[desde.month - 1].substring(1)} ${desde.year}';
  }
}

class KpiInforme {
  final String etiqueta;
  final String valor;
  final bool alerta;
  const KpiInforme(this.etiqueta, this.valor, {this.alerta = false});
}

/// Una serie del gráfico de barras: un valor por barra del período.
class SerieInforme {
  final String nombre;
  final List<double> valores;
  const SerieInforme(this.nombre, this.valores);
}

class InformeArea {
  final AreaInforme area;
  final RangoInforme rango;
  final List<KpiInforme> kpis;
  final String tituloGrafico;
  final List<SerieInforme> series;
  final String tituloTabla;
  final List<String> columnas;
  final List<List<String>> filas;
  final String? nota;

  const InformeArea({
    required this.area,
    required this.rango,
    required this.kpis,
    required this.tituloGrafico,
    required this.series,
    required this.tituloTabla,
    required this.columnas,
    required this.filas,
    this.nota,
  });

  bool get sinDatos => series.every((s) => s.valores.every((v) => v == 0)) && filas.isEmpty;
}
