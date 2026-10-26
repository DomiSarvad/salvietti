// Modelos de Informes por área (para el Gerente): un período (semana, mes, año
// o fechas elegidas), KPIs, series para el gráfico de barras (con proyección si
// el período está en curso) y una tabla de detalle. Todo independiente de la
// UI y del formato de exportación (PDF/Excel).

enum PeriodoInforme {
  semana('Semanal'),
  mes('Mensual'),
  anio('Anual'),
  fechas('Por fechas');

  final String etiqueta;
  const PeriodoInforme(this.etiqueta);
}

enum AreaInforme {
  general('General'),
  plan('Plan de producción'),
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
/// (lun…dom), el mes en semanas (Sem 1…Sem 5), el año en meses (Ene…Dic) y un
/// rango elegido a mano según su largo (días, semanas o meses). [hasta] es
/// exclusivo.
class RangoInforme {
  final PeriodoInforme periodo;
  final DateTime desde;
  final DateTime hasta;
  final List<DateTime> inicios; // inicio de cada barra
  final List<String> etiquetas; // texto de cada barra
  final String unidadBarra; // qué es cada barra (columna del Excel)

  const RangoInforme._(
      this.periodo, this.desde, this.hasta, this.inicios, this.etiquetas, this.unidadBarra);

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _mesesCortos = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// El período que contiene a [referencia]. Para [PeriodoInforme.fechas] da
  /// los últimos 30 días hasta [referencia] (lo normal es usar [entre]).
  factory RangoInforme.de(PeriodoInforme p, DateTime referencia) {
    final d = _dia(referencia);
    switch (p) {
      case PeriodoInforme.semana:
        final lunes = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        final inicios = [for (var i = 0; i < 7; i++) DateTime(lunes.year, lunes.month, lunes.day + i)];
        return RangoInforme._(p, lunes, DateTime(lunes.year, lunes.month, lunes.day + 7), inicios,
            [for (var i = 0; i < 7; i++) '${_dias[i]} ${inicios[i].day}'], 'Día');
      case PeriodoInforme.mes:
        final desde = DateTime(d.year, d.month, 1);
        final hasta = DateTime(d.year, d.month + 1, 1);
        final inicios = <DateTime>[];
        for (var dia = desde; dia.isBefore(hasta); dia = DateTime(dia.year, dia.month, dia.day + 7)) {
          inicios.add(dia);
        }
        return RangoInforme._(p, desde, hasta, inicios,
            [for (var i = 0; i < inicios.length; i++) 'Sem ${i + 1}'], 'Semana');
      case PeriodoInforme.anio:
        return RangoInforme._(p, DateTime(d.year, 1, 1), DateTime(d.year + 1, 1, 1),
            [for (var m = 1; m <= 12; m++) DateTime(d.year, m, 1)], _mesesCortos, 'Mes');
      case PeriodoInforme.fechas:
        return RangoInforme.entre(DateTime(d.year, d.month, d.day - 29), d);
    }
  }

  /// Rango elegido a mano, de [desde] a [ultimoDia] (los dos incluidos). Las
  /// barras se eligen por el largo: hasta 31 días, una por día; hasta ~4
  /// meses, una por semana (contando desde [desde]); más, una por mes.
  factory RangoInforme.entre(DateTime desde, DateTime ultimoDia) {
    var ini = _dia(desde), fin = _dia(ultimoDia);
    if (fin.isBefore(ini)) (ini, fin) = (fin, ini);
    final hasta = DateTime(fin.year, fin.month, fin.day + 1);
    final dias = hasta.difference(ini).inDays;
    String dm(DateTime x) => '${x.day}/${x.month}';
    final inicios = <DateTime>[];
    if (dias <= 31) {
      for (var x = ini; x.isBefore(hasta); x = DateTime(x.year, x.month, x.day + 1)) {
        inicios.add(x);
      }
      return RangoInforme._(
          PeriodoInforme.fechas, ini, hasta, inicios, [for (final x in inicios) dm(x)], 'Día');
    }
    if (dias <= 124) {
      for (var x = ini; x.isBefore(hasta); x = DateTime(x.year, x.month, x.day + 7)) {
        inicios.add(x);
      }
      return RangoInforme._(PeriodoInforme.fechas, ini, hasta, inicios,
          [for (final x in inicios) dm(x)], 'Semana desde');
    }
    for (var x = ini; x.isBefore(hasta); x = DateTime(x.year, x.month + 1, 1)) {
      inicios.add(x);
    }
    final variosAnios = ini.year != fin.year;
    return RangoInforme._(PeriodoInforme.fechas, ini, hasta, inicios, [
      for (final x in inicios)
        variosAnios ? '${_mesesCortos[x.month - 1]} ${x.year % 100}' : _mesesCortos[x.month - 1]
    ], 'Mes');
  }

  /// Último día incluido.
  DateTime get ultimoDia => DateTime(hasta.year, hasta.month, hasta.day - 1);

  int get dias => hasta.difference(desde).inDays;

  RangoInforme anterior() {
    switch (periodo) {
      case PeriodoInforme.semana:
        return RangoInforme.de(periodo, DateTime(desde.year, desde.month, desde.day - 1));
      case PeriodoInforme.mes:
        return RangoInforme.de(periodo, DateTime(desde.year, desde.month - 1, 1));
      case PeriodoInforme.anio:
        return RangoInforme.de(periodo, DateTime(desde.year - 1, 1, 1));
      case PeriodoInforme.fechas:
        // Mismo largo, justo antes.
        return RangoInforme.entre(DateTime(desde.year, desde.month, desde.day - dias),
            DateTime(desde.year, desde.month, desde.day - 1));
    }
  }

  RangoInforme siguiente() => periodo == PeriodoInforme.fechas
      ? RangoInforme.entre(hasta, DateTime(hasta.year, hasta.month, hasta.day + dias - 1))
      : RangoInforme.de(periodo, hasta);

  /// Índice de la barra a la que pertenece [fecha], o null si cae afuera.
  int? indiceDe(DateTime fecha) {
    if (fecha.isBefore(desde) || !fecha.isBefore(hasta)) return null;
    for (var i = inicios.length - 1; i >= 0; i--) {
      if (!fecha.isBefore(inicios[i])) return i;
    }
    return null;
  }

  /// Fin (exclusivo) de la barra [i].
  DateTime finDe(int i) => i + 1 < inicios.length ? inicios[i + 1] : hasta;

  String get titulo {
    String f(DateTime x) => '${x.day}/${x.month}/${x.year}';
    final fin = ultimoDia;
    // Sin repetir el año si es el mismo (entra mejor en un celular).
    final ini = desde.year == fin.year ? '${desde.day}/${desde.month}' : f(desde);
    switch (periodo) {
      case PeriodoInforme.semana:
        return 'Semana del $ini al ${f(fin)}';
      case PeriodoInforme.mes:
        return '${_meses[desde.month - 1][0].toUpperCase()}${_meses[desde.month - 1].substring(1)} ${desde.year}';
      case PeriodoInforme.anio:
        return 'Año ${desde.year}';
      case PeriodoInforme.fechas:
        return 'Del $ini al ${f(fin)}';
    }
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

  /// Lo que se estima que falta en cada barra si se sigue al mismo ritmo.
  /// Solo en el período en curso; null si ya terminó (ver InformesService).
  final List<double>? proyeccion;
  const SerieInforme(this.nombre, this.valores, {this.proyeccion});

  double get total => valores.fold(0.0, (s, v) => s + v);
  double? get totalProyectado =>
      proyeccion == null ? null : total + proyeccion!.fold(0.0, (s, v) => s + v);

  SerieInforme conProyeccion(List<double> p) => SerieInforme(nombre, valores, proyeccion: p);
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

  /// Texto con el que se filtró (vacío = todo). Va en el encabezado del PDF/Excel.
  final String busqueda;

  /// Cuántas barras se dibujan: en un período en curso, hasta la de hoy (en
  /// el año, de enero al mes actual). Antes se dibujaban también los meses
  /// que faltan con lo estimado, y parecía que en diciembre hubo movimiento.
  /// null = todas.
  final int? barrasHastaHoy;

  /// El período anterior (mes pasado, año pasado…) para comparar barra a
  /// barra, con el mismo largo que [series]. null = sin comparar.
  final List<SerieInforme>? anteriores;
  final String? tituloAnterior;

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
    this.busqueda = '',
    this.barrasHastaHoy,
    this.anteriores,
    this.tituloAnterior,
  });

  int get barrasVisibles => barrasHastaHoy ?? rango.etiquetas.length;

  /// Suma de las primeras [n] barras de una serie (para comparar "a la misma
  /// altura": enero–octubre de este año contra enero–octubre del anterior).
  static double sumaHasta(SerieInforme s, int n) =>
      s.valores.take(n).fold(0.0, (a, v) => a + v);

  bool get sinDatos => series.every((s) => s.valores.every((v) => v == 0)) && filas.isEmpty;

  bool get tieneProyeccion => series.any((s) => s.proyeccion != null);

  InformeArea conSeries(List<SerieInforme> nuevas, {int? barrasHastaHoy}) =>
      _copia(series: nuevas, barrasHastaHoy: barrasHastaHoy);
  InformeArea conBusqueda(String texto) => _copia(busqueda: texto);

  /// Agrega el período anterior para comparar. Sus series se ajustan al largo
  /// de las actuales (un mes puede tener 4 o 5 semanas).
  InformeArea conAnterior(InformeArea anterior) => _copia(
        anteriores: [
          for (final s in anterior.series)
            SerieInforme(s.nombre, [
              for (var b = 0; b < rango.etiquetas.length; b++)
                b < s.valores.length ? s.valores[b] : 0,
            ]),
        ],
        tituloAnterior: anterior.rango.titulo,
      );

  /// Solo algunos indicadores (la búsqueda era el nombre de uno).
  InformeArea soloIndicadores({
    required List<KpiInforme> kpis,
    required List<SerieInforme> series,
    required List<List<String>> filas,
    required String busqueda,
  }) =>
      _copia(kpis: kpis, series: series, filas: filas, busqueda: busqueda);

  InformeArea _copia({
    List<KpiInforme>? kpis,
    List<SerieInforme>? series,
    List<List<String>>? filas,
    String? busqueda,
    int? barrasHastaHoy,
    List<SerieInforme>? anteriores,
    String? tituloAnterior,
  }) =>
      InformeArea(
        area: area,
        rango: rango,
        kpis: kpis ?? this.kpis,
        tituloGrafico: tituloGrafico,
        series: series ?? this.series,
        tituloTabla: tituloTabla,
        columnas: columnas,
        filas: filas ?? this.filas,
        nota: nota,
        busqueda: busqueda ?? this.busqueda,
        barrasHastaHoy: barrasHastaHoy ?? this.barrasHastaHoy,
        anteriores: anteriores ?? this.anteriores,
        tituloAnterior: tituloAnterior ?? this.tituloAnterior,
      );
}
