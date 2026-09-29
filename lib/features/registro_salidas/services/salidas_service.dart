import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/salidas_modelos.dart';
import '../repositories/salidas_repository.dart';

/// Reglas del módulo de Registro de salidas: quién puede abrir un reporte
/// del día, agregarle líneas por sabor/formato y cerrarlo. No conoce
/// widgets; el total de botellas lo calcula el servidor (vista
/// `salidas_reporte_detalle`).
class SalidasService extends ChangeNotifier {
  SalidasService(this._repo, this._usuario);

  final SalidasRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Presentacion> presentaciones = [];
  List<ReporteSalidas> reportes = [];
  List<PlanillaFila> planilla = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.salidas, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeEditar => _puede(Accion.editar);

  List<ReporteSalidas> get abiertos =>
      reportes.where((r) => r.estado == EstadoReporte.abierto).toList();
  List<ReporteSalidas> get cerrados =>
      reportes.where((r) => r.estado == EstadoReporte.cerrado).toList();

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    notifyListeners();
    if (!puedeVer) {
      cargando = false;
      notifyListeners();
      return;
    }
    try {
      final r = await Future.wait([
        _repo.sabores(),
        _repo.presentaciones(),
        _repo.reportes(),
        _repo.planilla(),
      ]);
      sabores = r[0] as List<Sabor>;
      presentaciones = r[1] as List<Presentacion>;
      reportes = r[2] as List<ReporteSalidas>;
      planilla = r[3] as List<PlanillaFila>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Registro de salidas. Revisá la conexión o que la '
          'migración v34 esté ejecutada.';
      if (kDebugMode) debugPrint('SalidasService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<Set<int>> presentacionesDe(int saborId) => _repo.presentacionesDe(saborId);
  Future<List<LineaSalidas>> lineasDe(ReporteSalidas r) => _repo.lineasDe(r.id);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> crearReporte(String? turno) async {
    if (!puedeCrear) return 'No tenés permiso para abrir un reporte de salidas.';
    if (turno == null) return 'Elegí el turno.';
    return _ejecutar(() => _repo.crearReporte(turno));
  }

  Future<String?> guardarLinea(ReporteSalidas r, DatosLinea d) async {
    if (!puedeEditar) return 'No tenés permiso para editar este reporte.';
    if (r.estado != EstadoReporte.abierto) return 'Este reporte ya está cerrado.';
    final valores = [
      d.petPalets, d.petPaquetesLibres, d.petBotellasLibres,
      d.vidFilas, d.vidCajasLibres, d.vidBotellasLibres,
    ];
    if (valores.any((v) => v != null && v < 0)) return 'Ningún valor puede ser negativo.';
    return _ejecutar(() => _repo.guardarLinea(r.id, d));
  }

  Future<String?> eliminarLinea(int idLinea) async {
    if (!puedeEditar) return 'No tenés permiso para editar este reporte.';
    return _ejecutar(() => _repo.eliminarLinea(idLinea));
  }

  Future<String?> cerrarReporte(ReporteSalidas r, String? observaciones) async {
    if (!puedeEditar) return 'No tenés permiso para cerrar este reporte.';
    if (r.estado != EstadoReporte.abierto) return 'Este reporte ya está cerrado.';
    return _ejecutar(() => _repo.cerrarReporte(r.id, observaciones));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioSalidas catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('SalidasService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
