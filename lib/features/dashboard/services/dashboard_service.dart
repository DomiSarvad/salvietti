import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../inventario/models/almacen.dart';
import '../../inventario/models/existencia_item.dart';
import '../../mermas/models/mermas_modelos.dart';
import '../models/dashboard_modelos.dart';
import '../repositories/dashboard_repository.dart';

/// Resumen de un almacén, para su tarjeta en el Inicio.
class ResumenAlmacen {
  final Almacen almacen;
  final int total;
  final int criticos;
  final int bajos;
  final int optimos;
  const ResumenAlmacen({
    required this.almacen,
    required this.total,
    required this.criticos,
    required this.bajos,
    required this.optimos,
  });

  /// El semáforo del almacén completo: el peor estado de cualquiera de sus
  /// ítems. Null si el almacén todavía no tiene ítems cargados.
  EstadoStock? get estado {
    if (total == 0) return null;
    if (criticos > 0) return EstadoStock.critico;
    if (bajos > 0) return EstadoStock.bajo;
    return EstadoStock.optimo;
  }
}

/// Resumen de merma de un área, para el gráfico de barras del Inicio.
class ResumenMermaArea {
  final String area;
  final double porcentajePromedio;
  final bool alerta;
  final int eventos;
  const ResumenMermaArea({
    required this.area,
    required this.porcentajePromedio,
    required this.alerta,
    required this.eventos,
  });
}

/// Reglas del Inicio: qué almacenes le tocan al rol (Módulo 1 — el mismo
/// permiso `inventario_<almacén>` que ya decide Almacenes), y los resúmenes
/// que se arman con eso. No conoce widgets.
class DashboardService extends ChangeNotifier {
  DashboardService(this._repo, this._usuario);

  final DashboardRepository _repo;
  final Usuario _usuario;

  List<Almacen> almacenesVisibles = [];
  List<ExistenciaItem> existencias = [];
  List<MovimientoReciente> movimientos = [];
  List<EventoMerma> mermas = [];

  bool cargando = true;
  String? error;

  Suscripcion? _canalStock;
  Suscripcion? _canalMermas;
  Timer? _debounceStock;
  Timer? _debounceMermas;

  bool _puedeVer(String almacenId) =>
      _usuario.puede(Modulo.inventarioDe(almacenId), Accion.ver, reglaAnterior: false);

  bool get puedeVerMermas => _usuario.puede(Modulo.mermas, Accion.ver, reglaAnterior: false);

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final todos = await _repo.almacenes();
      almacenesVisibles = [for (final a in todos) if (_puedeVer(a.id)) a];
      if (almacenesVisibles.isEmpty) {
        existencias = [];
        movimientos = [];
        mermas = [];
        cargando = false;
        notifyListeners();
        return;
      }
      final ids = [for (final a in almacenesVisibles) a.id];
      final r = await Future.wait([
        _repo.existenciasDe(ids),
        _repo.movimientosRecientes(ids),
        if (puedeVerMermas) _repo.mermasRecientes() else Future.value(<EventoMerma>[]),
      ]);
      existencias = r[0] as List<ExistenciaItem>;
      movimientos = r[1] as List<MovimientoReciente>;
      mermas = r[2] as List<EventoMerma>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar el Inicio. Revisá la conexión.';
      if (kDebugMode) debugPrint('DashboardService: $e');
    }
    cargando = false;
    notifyListeners();
    _suscribirTiempoReal();
  }

  Future<void> recargar() => iniciar();

  /// Se suscribe una sola vez (si ya hay canales abiertos, no repite) a los
  /// cambios que afectan al Inicio, para que las tarjetas y los gráficos se
  /// actualicen solos sin que alguien tenga que refrescar la pantalla.
  void _suscribirTiempoReal() {
    if (almacenesVisibles.isEmpty) return;
    _canalStock ??= _repo.escucharStock(() {
      _debounceStock?.cancel();
      _debounceStock = Timer(const Duration(milliseconds: 400), _recargarStockSilencioso);
    });
    if (puedeVerMermas) {
      _canalMermas ??= _repo.escucharMermas(() {
        _debounceMermas?.cancel();
        _debounceMermas = Timer(const Duration(milliseconds: 400), _recargarMermasSilencioso);
      });
    }
  }

  Future<void> _recargarStockSilencioso() async {
    try {
      final ids = [for (final a in almacenesVisibles) a.id];
      final r = await Future.wait([
        _repo.existenciasDe(ids),
        _repo.movimientosRecientes(ids),
      ]);
      existencias = r[0] as List<ExistenciaItem>;
      movimientos = r[1] as List<MovimientoReciente>;
      error = null; // si estaba mostrando el error de carga, ya se recuperó solo
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('DashboardService (tiempo real, stock): $e');
    }
  }

  Future<void> _recargarMermasSilencioso() async {
    try {
      mermas = await _repo.mermasRecientes();
      error = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('DashboardService (tiempo real, mermas): $e');
    }
  }

  @override
  void dispose() {
    _debounceStock?.cancel();
    _debounceMermas?.cancel();
    _canalStock?.cancelar();
    _canalMermas?.cancelar();
    super.dispose();
  }

  List<EventoMerma> get mermasConAlerta => mermas.where((e) => e.alerta).toList();

  /// Para el gráfico de mermas del Inicio: un valor por área (promedio de
  /// sus eventos recientes), con la alerta si alguno de esos eventos superó
  /// el 3 %.
  List<ResumenMermaArea> get mermasPorArea {
    final porArea = <String, List<EventoMerma>>{};
    for (final e in mermas) {
      porArea.putIfAbsent(e.area, () => []).add(e);
    }
    final resultado = [
      for (final entrada in porArea.entries)
        ResumenMermaArea(
          area: entrada.key,
          porcentajePromedio: _promedio(entrada.value.map((e) => e.porcentaje)),
          alerta: entrada.value.any((e) => e.alerta),
          eventos: entrada.value.length,
        ),
    ]..sort((a, b) => b.porcentajePromedio.compareTo(a.porcentajePromedio));
    return resultado;
  }

  double _promedio(Iterable<double?> valores) {
    final conDato = valores.whereType<double>().toList();
    if (conDato.isEmpty) return 0;
    return conDato.reduce((a, b) => a + b) / conDato.length;
  }

  SituacionStock situacionDe(ExistenciaItem e) {
    // Sin stock es crítico aunque no haya consumo cargado todavía (un
    // ítem recién creado, o uno cuyo consumo nunca se registró, no debe
    // quedar invisible en el semáforo solo porque falta ese dato).
    if (e.cantidadSistema <= 0) return SituacionStock.critico;
    final dias = e.diasExistencia;
    if (dias == null) return SituacionStock.sinDatos;
    switch (SemaforoStock.evaluar(dias)) {
      case EstadoStock.critico:
        return SituacionStock.critico;
      case EstadoStock.bajo:
        return SituacionStock.bajo;
      case EstadoStock.optimo:
        return SituacionStock.optimo;
    }
  }

  List<ResumenAlmacen> get resumenes => [
        for (final a in almacenesVisibles)
          ResumenAlmacen(
            almacen: a,
            total: existencias.where((e) => e.almacenId == a.id).length,
            criticos: existencias
                .where((e) => e.almacenId == a.id && situacionDe(e) == SituacionStock.critico)
                .length,
            bajos: existencias
                .where((e) => e.almacenId == a.id && situacionDe(e) == SituacionStock.bajo)
                .length,
            optimos: existencias
                .where((e) => e.almacenId == a.id && situacionDe(e) == SituacionStock.optimo)
                .length,
          ),
      ];

  /// Los que más urgen reponer: con días de existencia, ordenados de menor
  /// a mayor (los sin dato de consumo no entran acá, no se sabe si urgen).
  List<ExistenciaItem> get enRiesgo {
    final conDato = existencias.where((e) => e.diasExistencia != null).toList()
      ..sort((a, b) => a.diasExistencia!.compareTo(b.diasExistencia!));
    return conDato.where((e) => e.diasExistencia! <= 7).toList();
  }

  /// Para el gráfico de barras: primero los críticos, después los bajos,
  /// y recién ahí por cantidad absoluta — así no lo tapan ítems del
  /// catálogo en 0 que nunca tuvieron movimiento ni consumo cargado.
  List<ExistenciaItem> get menorStock {
    int prioridad(ExistenciaItem e) {
      switch (situacionDe(e)) {
        case SituacionStock.critico:
          return 0;
        case SituacionStock.bajo:
          return 1;
        case SituacionStock.optimo:
          return 2;
        case SituacionStock.sinDatos:
          return 3;
      }
    }

    final orden = [...existencias]
      ..sort((a, b) {
        final p = prioridad(a).compareTo(prioridad(b));
        return p != 0 ? p : a.cantidadSistema.compareTo(b.cantidadSistema);
      });
    return orden.take(6).toList();
  }
}

enum SituacionStock { sinDatos, optimo, bajo, critico }
