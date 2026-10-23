import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../utils/formatters.dart';
import '../models/informes_modelos.dart';
import '../repositories/informes_repository.dart';

/// Arma los informes por área para el Gerente: elige el período (semana o
/// mes), trae las filas del rango y las agrega en KPIs, series para el
/// gráfico y una tabla de detalle. Solo cuenta lo FINALIZADO (lo en curso no
/// tiene resultado todavía; lo anulado no se produjo). No conoce widgets.
class InformesService extends ChangeNotifier {
  InformesService(this._repo, this._usuario, {DateTime Function()? ahora})
      : _ahora = ahora ?? DateTime.now {
    rango = RangoInforme.de(PeriodoInforme.semana, _ahora());
  }

  final InformesRepository _repo;
  final Usuario _usuario;
  final DateTime Function() _ahora;

  /// Merma por encima de esto se marca en alerta (mismo criterio que v35).
  static const limiteMerma = 3.0;

  AreaInforme area = AreaInforme.general;
  late RangoInforme rango;
  InformeArea? informe;
  bool cargando = false;
  String? error;
  int _pedido = 0; // descarta respuestas viejas si se cambia rápido de filtro

  bool get puedeVer => _usuario.puede(Modulo.informeProduccion, Accion.ver, reglaAnterior: false);

  /// No se puede avanzar más allá del período actual (no hay datos del futuro).
  bool get puedeAvanzar => !rango.hasta.isAfter(_ahora());

  Future<void> iniciar() => cargar();

  void elegirArea(AreaInforme a) {
    if (a == area) return;
    area = a;
    cargar();
  }

  void elegirPeriodo(PeriodoInforme p) {
    if (p == rango.periodo) return;
    rango = RangoInforme.de(p, _ahora());
    cargar();
  }

  void anterior() {
    rango = rango.anterior();
    cargar();
  }

  void siguiente() {
    if (!puedeAvanzar) return;
    rango = rango.siguiente();
    cargar();
  }

  Future<void> cargar() async {
    if (!puedeVer) return;
    final pedido = ++_pedido;
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final r = await construir(area, rango);
      if (pedido != _pedido) return;
      informe = r;
    } catch (e) {
      if (pedido != _pedido) return;
      if (kDebugMode) debugPrint('InformesService: $e');
      informe = null;
      error = 'No se pudo armar el informe de ${area.titulo}. Revisá la conexión.';
    }
    cargando = false;
    notifyListeners();
  }

  // ------------------------------------------------------------- utilidades

  static double _n(Object? v) => v is num ? v.toDouble() : 0;

  static DateTime _fecha(Map<String, dynamic> f, String col) {
    final s = f[col] as String;
    final d = DateTime.parse(s);
    return s.length <= 10 ? d : d.toLocal(); // `date` vs `timestamptz`
  }

  static String _nombre(Map<String, dynamic> f, String tabla, [String col = 'nombre']) =>
      ((f[tabla] as Map?)?[col] as String?) ?? 'Sin dato';

  /// Suma [valor] de cada fila en la barra que le toca por su fecha.
  static List<double> _serie(RangoInforme r, List<Map<String, dynamic>> filas, String colFecha,
      double Function(Map<String, dynamic>) valor) {
    final out = List<double>.filled(r.inicios.length, 0);
    for (final f in filas) {
      final i = r.indiceDe(_fecha(f, colFecha));
      if (i != null) out[i] += valor(f);
    }
    return out;
  }

  static Map<String, List<Map<String, dynamic>>> _agrupar(
      List<Map<String, dynamic>> filas, String Function(Map<String, dynamic>) clave) {
    final m = <String, List<Map<String, dynamic>>>{};
    for (final f in filas) {
      m.putIfAbsent(clave(f), () => []).add(f);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  static double _suma(Iterable<Map<String, dynamic>> filas, String col) =>
      filas.fold(0.0, (s, f) => s + _n(f[col]));

  static String _pct(double v) => '${fmtNum(v, decimales: 1)} %';

  static double _porcentaje(double parte, double total) => total <= 0 ? 0 : parte * 100 / total;

  Future<List<Map<String, dynamic>>> _filas(RangoInforme r, String tabla, String select,
          {String fecha = 'fecha', bool esDia = true}) =>
      _repo.filas(
          tabla: tabla,
          select: select,
          columnaFecha: fecha,
          desde: r.desde,
          hasta: r.hasta,
          fechaEsDia: esDia);

  // --------------------------------------------------------------- por área

  Future<InformeArea> construir(AreaInforme a, RangoInforme r) {
    switch (a) {
      case AreaInforme.general:
        return _general(r);
      case AreaInforme.jarabes:
        return _jarabes(r);
      case AreaInforme.soplado:
        return _corridas(r, AreaInforme.soplado, 'soplado_corridas',
            'fecha, estado, botellas_sopladas, merma_soplado, merma_preforma, merma_etiquetado, '
                'tiempo_parada_minutos, sabores(nombre)',
            producido: 'botellas_sopladas',
            etiquetaProducido: 'Botellas sopladas',
            merma: (f) => _n(f['merma_soplado']) + _n(f['merma_preforma']) + _n(f['merma_etiquetado']),
            extra: (fs) => KpiInforme('Tiempo de parada', '${fmtNum(_suma(fs, 'tiempo_parada_minutos'), decimales: 0)} min'));
      case AreaInforme.llenadora:
        return _corridas(r, AreaInforme.llenadora, 'llenadora_corridas',
            'fecha, estado, botellas_llenadas, botellas_desechadas, sabores(nombre)',
            producido: 'botellas_llenadas',
            etiquetaProducido: 'Botellas llenadas',
            merma: (f) => _n(f['botellas_desechadas']));
      case AreaInforme.codificacion:
        return _corridas(r, AreaInforme.codificacion, 'codificacion_corridas',
            'fecha, estado, botellas_codificadas, botellas_mal_tapadas, impurezas, sabores(nombre)',
            producido: 'botellas_codificadas',
            etiquetaProducido: 'Botellas codificadas',
            merma: (f) => _n(f['botellas_mal_tapadas']) + _n(f['impurezas']));
      case AreaInforme.calidad:
        return _calidad(r);
      case AreaInforme.produccion:
        return _produccion(r);
      case AreaInforme.mermas:
        return _mermas(r);
      case AreaInforme.almacen:
        return _almacen(r);
      case AreaInforme.soda:
        return _soda(r);
    }
  }

  Future<InformeArea> _jarabes(RangoInforme r) async {
    final todas = await _filas(r, 'jarabes_preparados',
        'fecha, estado, litros, cantidad_preparados, brix, sabores(nombre)');
    final fs = todas.where((f) => f['estado'] == 'finalizada').toList();
    final anulados = todas.where((f) => f['estado'] == 'anulada').length;
    final conBrix = fs.where((f) => f['brix'] != null).toList();
    final brix = conBrix.isEmpty ? null : _suma(conBrix, 'brix') / conBrix.length;
    final porSabor = _agrupar(fs, (f) => _nombre(f, 'sabores'));
    return InformeArea(
      area: AreaInforme.jarabes,
      rango: r,
      kpis: [
        KpiInforme('Preparados finalizados', '${fs.length}'),
        KpiInforme('Litros preparados', fmtNum(_suma(fs, 'litros'), decimales: 0)),
        KpiInforme('Brix promedio', brix == null ? '—' : fmtNum(brix, decimales: 1)),
        KpiInforme('Anulados', '$anulados', alerta: anulados > 0),
      ],
      tituloGrafico: 'Litros preparados',
      series: [SerieInforme('Litros', _serie(r, fs, 'fecha', (f) => _n(f['litros'])))],
      tituloTabla: 'Por sabor',
      columnas: const ['Sabor', 'Preparados', 'Litros', 'Brix prom.'],
      filas: [
        for (final e in porSabor.entries)
          () {
            final b = e.value.where((f) => f['brix'] != null).toList();
            return [
              e.key,
              '${e.value.length}',
              fmtNum(_suma(e.value, 'litros'), decimales: 0),
              b.isEmpty ? '—' : fmtNum(_suma(b, 'brix') / b.length, decimales: 1),
            ];
          }()
      ],
    );
  }

  /// Soplado, Llenadora y Codificación tienen la misma forma: corridas con
  /// algo producido y algo desechado.
  Future<InformeArea> _corridas(
    RangoInforme r,
    AreaInforme a,
    String tabla,
    String select, {
    required String producido,
    required String etiquetaProducido,
    required double Function(Map<String, dynamic>) merma,
    KpiInforme Function(List<Map<String, dynamic>>)? extra,
  }) async {
    final fs = (await _filas(r, tabla, select)).where((f) => f['estado'] == 'finalizada').toList();
    final prod = _suma(fs, producido);
    final mer = fs.fold(0.0, (s, f) => s + merma(f));
    final pct = _porcentaje(mer, prod);
    final porSabor = _agrupar(fs, (f) => _nombre(f, 'sabores'));
    return InformeArea(
      area: a,
      rango: r,
      kpis: [
        KpiInforme('Corridas finalizadas', '${fs.length}'),
        KpiInforme(etiquetaProducido, fmtNum(prod, decimales: 0)),
        KpiInforme('Merma (unidades)', fmtNum(mer, decimales: 0)),
        KpiInforme('% de merma', _pct(pct), alerta: pct > limiteMerma),
        if (extra != null) extra(fs),
      ],
      tituloGrafico: '$etiquetaProducido y merma',
      series: [
        SerieInforme(etiquetaProducido, _serie(r, fs, 'fecha', (f) => _n(f[producido]))),
        SerieInforme('Merma', _serie(r, fs, 'fecha', merma)),
      ],
      tituloTabla: 'Por sabor',
      columnas: const ['Sabor', 'Corridas', 'Producido', 'Merma', '% merma'],
      filas: [
        for (final e in porSabor.entries)
          () {
            final p = _suma(e.value, producido);
            final m = e.value.fold(0.0, (s, f) => s + merma(f));
            return [
              e.key,
              '${e.value.length}',
              fmtNum(p, decimales: 0),
              fmtNum(m, decimales: 0),
              _pct(_porcentaje(m, p)),
            ];
          }()
      ],
      nota: 'Merma en alerta si supera el ${fmtNum(limiteMerma, decimales: 0)} % de lo producido.',
    );
  }

  Future<InformeArea> _calidad(RangoInforme r) async {
    final fs = await _filas(r, 'calidad_analisis', 'fecha, resultado, ph, brix_diluido, aspecto',
        esDia: false);
    final conformes = fs.where((f) => f['resultado'] == 'conforme').toList();
    final no = fs.where((f) => f['resultado'] == 'no_conforme').toList();
    final conPh = fs.where((f) => f['ph'] != null).toList();
    return InformeArea(
      area: AreaInforme.calidad,
      rango: r,
      kpis: [
        KpiInforme('Análisis', '${fs.length}'),
        KpiInforme('Conformes', '${conformes.length}'),
        KpiInforme('No conformes', '${no.length}', alerta: no.isNotEmpty),
        KpiInforme('% de conformidad', _pct(_porcentaje(conformes.length.toDouble(), fs.length.toDouble()))),
        KpiInforme('pH promedio', conPh.isEmpty ? '—' : fmtNum(_suma(conPh, 'ph') / conPh.length)),
      ],
      tituloGrafico: 'Análisis conformes y no conformes',
      series: [
        SerieInforme('Conformes', _serie(r, conformes, 'fecha', (_) => 1)),
        SerieInforme('No conformes', _serie(r, no, 'fecha', (_) => 1)),
      ],
      tituloTabla: 'Análisis no conformes',
      columnas: const ['Fecha', 'Brix', 'pH', 'Aspecto'],
      filas: [
        for (final f in no)
          [
            fmtFechaHora(_fecha(f, 'fecha')),
            f['brix_diluido'] == null ? '—' : fmtNum(_n(f['brix_diluido'])),
            f['ph'] == null ? '—' : fmtNum(_n(f['ph'])),
            (f['aspecto'] as String?) ?? '—',
          ]
      ],
    );
  }

  Future<InformeArea> _produccion(RangoInforme r) async {
    final fs = await _filas(r, 'salidas_planilla', 'fecha, sabor, presentacion, total_botellas');
    final total = _suma(fs, 'total_botellas');
    final dias = fs.map((f) => f['fecha']).toSet().length;
    final porProducto = _agrupar(fs, (f) => '${f['sabor']} · ${f['presentacion']}');
    return InformeArea(
      area: AreaInforme.produccion,
      rango: r,
      kpis: [
        KpiInforme('Botellas producidas', fmtNum(total, decimales: 0)),
        KpiInforme('Días con producción', '$dias'),
        KpiInforme('Productos distintos', '${porProducto.length}'),
      ],
      tituloGrafico: 'Botellas producidas (Registro de salidas)',
      series: [SerieInforme('Botellas', _serie(r, fs, 'fecha', (f) => _n(f['total_botellas'])))],
      tituloTabla: 'Por producto',
      columnas: const ['Producto', 'Botellas'],
      filas: [
        for (final e in porProducto.entries) [e.key, fmtNum(_suma(e.value, 'total_botellas'), decimales: 0)]
      ],
      nota: 'En Vidrio el total puede ser parcial (falta la equivalencia de filas por palet).',
    );
  }

  Future<InformeArea> _mermas(RangoInforme r) async {
    final fs = await _filas(r, 'mermas_consolidado', 'fecha, area, total_merma, producido, porcentaje, alerta');
    final conPct = fs.where((f) => f['porcentaje'] != null).toList();
    final prom = conPct.isEmpty ? 0.0 : _suma(conPct, 'porcentaje') / conPct.length;
    final alertas = fs.where((f) => f['alerta'] == true).length;
    final porArea = _agrupar(fs, (f) => (f['area'] as String?) ?? 'Sin área');
    return InformeArea(
      area: AreaInforme.mermas,
      rango: r,
      kpis: [
        KpiInforme('Eventos de merma', '${fs.length}'),
        KpiInforme('Merma total (unidades)', fmtNum(_suma(fs, 'total_merma'), decimales: 0)),
        KpiInforme('% promedio', _pct(prom), alerta: prom > limiteMerma),
        KpiInforme('Eventos en alerta', '$alertas', alerta: alertas > 0),
      ],
      tituloGrafico: 'Merma total',
      series: [SerieInforme('Merma', _serie(r, fs, 'fecha', (f) => _n(f['total_merma'])))],
      tituloTabla: 'Por área',
      columnas: const ['Área', 'Eventos', 'Merma', '% prom.', 'Alertas'],
      filas: [
        for (final e in porArea.entries)
          () {
            final p = e.value.where((f) => f['porcentaje'] != null).toList();
            return [
              e.key,
              '${e.value.length}',
              fmtNum(_suma(e.value, 'total_merma'), decimales: 0),
              p.isEmpty ? '—' : _pct(_suma(p, 'porcentaje') / p.length),
              '${e.value.where((f) => f['alerta'] == true).length}',
            ];
          }()
      ],
    );
  }

  Future<InformeArea> _almacen(RangoInforme r) async {
    final movs = await _filas(r, 'inv_movimientos', 'fecha, tipo, almacen_id', esDia: false);
    List<Map<String, dynamic>> compras = const [];
    try {
      compras = await _filas(r, 'compras_pedidos', 'fecha, estado', esDia: false);
    } catch (_) {
      // Sin la migración v43 todavía: el informe sale igual, sin compras.
    }
    bool es(Map<String, dynamic> f, String t) => f['tipo'] == t;
    final entradas = movs.where((f) => es(f, 'entrada')).toList();
    final salidas = movs.where((f) => es(f, 'salida')).toList();
    final ajustes = movs.where((f) => es(f, 'ajuste') || es(f, 'transferencia')).length;
    int cuenta(String e) => compras.where((f) => f['estado'] == e).length;
    final porAlmacen = _agrupar(movs, (f) => (f['almacen_id'] as String?) ?? '—');
    return InformeArea(
      area: AreaInforme.almacen,
      rango: r,
      kpis: [
        KpiInforme('Entradas', '${entradas.length}'),
        KpiInforme('Salidas', '${salidas.length}'),
        KpiInforme('Ajustes', '$ajustes'),
        KpiInforme('Compras aprobadas', '${cuenta('aprobado')}'),
        KpiInforme('Compras pendientes', '${cuenta('pendiente')}', alerta: cuenta('pendiente') > 0),
      ],
      tituloGrafico: 'Movimientos de stock',
      series: [
        SerieInforme('Entradas', _serie(r, entradas, 'fecha', (_) => 1)),
        SerieInforme('Salidas', _serie(r, salidas, 'fecha', (_) => 1)),
      ],
      tituloTabla: 'Por almacén',
      columnas: const ['Almacén', 'Entradas', 'Salidas', 'Ajustes'],
      filas: [
        for (final e in porAlmacen.entries)
          [
            e.key,
            '${e.value.where((f) => es(f, 'entrada')).length}',
            '${e.value.where((f) => es(f, 'salida')).length}',
            '${e.value.where((f) => es(f, 'ajuste') || es(f, 'transferencia')).length}',
          ]
      ],
      nota: 'Cuenta movimientos, no unidades: cada ítem se mide en su propia unidad.',
    );
  }

  Future<InformeArea> _soda(RangoInforme r) async {
    final fs = await _filas(r, 'soda_entregas', 'fecha_hora, cantidad, area_recibe, inv_items(unidad)',
        fecha: 'fecha_hora', esDia: false);
    final unidad = fs.isEmpty ? '' : _nombre(fs.first, 'inv_items', 'unidad');
    final porArea = _agrupar(fs, (f) => (f['area_recibe'] as String?) ?? 'Sin área');
    return InformeArea(
      area: AreaInforme.soda,
      rango: r,
      kpis: [
        KpiInforme('Entregas', '${fs.length}'),
        KpiInforme('Total entregado', '${fmtNum(_suma(fs, 'cantidad'))} $unidad'),
      ],
      tituloGrafico: 'Soda Cáustica entregada',
      series: [SerieInforme('Cantidad', _serie(r, fs, 'fecha_hora', (f) => _n(f['cantidad'])))],
      tituloTabla: 'Por área que recibe',
      columnas: const ['Área', 'Entregas', 'Cantidad'],
      filas: [
        for (final e in porArea.entries) [e.key, '${e.value.length}', fmtNum(_suma(e.value, 'cantidad'))]
      ],
    );
  }

  /// Resumen general: lo principal de cada área, en una sola vista.
  Future<InformeArea> _general(RangoInforme r) async {
    final partes = await Future.wait([
      _produccion(r),
      _corridas(r, AreaInforme.soplado, 'soplado_corridas',
          'fecha, estado, botellas_sopladas, merma_soplado, merma_preforma, merma_etiquetado, sabores(nombre)',
          producido: 'botellas_sopladas',
          etiquetaProducido: 'Botellas sopladas',
          merma: (f) => _n(f['merma_soplado']) + _n(f['merma_preforma']) + _n(f['merma_etiquetado'])),
      _jarabes(r),
      _mermas(r),
      _calidad(r),
    ]);
    final prod = partes[0], sop = partes[1], jar = partes[2], mer = partes[3], cal = partes[4];
    KpiInforme k(InformeArea i, int n) => i.kpis[n];
    return InformeArea(
      area: AreaInforme.general,
      rango: r,
      kpis: [
        k(prod, 0), // botellas producidas
        k(sop, 1), // botellas sopladas
        k(jar, 1), // litros de jarabe
        k(mer, 2), // % promedio de merma
        k(cal, 3), // % conformidad
      ],
      tituloGrafico: 'Producción',
      series: [prod.series.first, sop.series.first],
      tituloTabla: 'Resumen por área',
      columnas: const ['Área', 'Indicador', 'Valor'],
      filas: [
        for (final i in partes)
          for (final kpi in i.kpis) [i.area.titulo, kpi.etiqueta, kpi.valor]
      ],
    );
  }
}
