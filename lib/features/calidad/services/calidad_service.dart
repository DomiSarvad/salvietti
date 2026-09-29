import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/calidad_modelos.dart';
import '../repositories/calidad_repository.dart';

/// Reglas de Control de Calidad: quién registra un análisis, validación del
/// formulario (Brix, pH, acción obligatoria si no conforme) y la bandeja de
/// preparados pendientes. No conoce widgets.
class CalidadService extends ChangeNotifier {
  CalidadService(this._repo, this._usuario);

  final CalidadRepository _repo;
  final Usuario _usuario;

  List<PreparadoPendiente> pendientes = [];
  List<AnalisisCalidad> analisis = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.calidad, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeEditar => _puede(Accion.editar);

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
      final r = await Future.wait([_repo.pendientes(), _repo.analisis()]);
      pendientes = r[0] as List<PreparadoPendiente>;
      analisis = r[1] as List<AnalisisCalidad>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Calidad. Revisá la conexión o que la '
          'migración v27 esté ejecutada.';
      if (kDebugMode) debugPrint('CalidadService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<String?> registrarAnalisis(NuevoAnalisis a) async {
    if (!puedeCrear) return 'No tenés permiso para registrar análisis de Calidad.';
    if (a.brixDiluido == null || a.brixDiluido!.isNaN || a.brixDiluido! < 0 || a.brixDiluido! > 100) {
      return 'Ingresá un Brix válido (0 a 100).';
    }
    if (a.ph == null || a.ph!.isNaN || a.ph! < 0 || a.ph! > 14) {
      return 'Ingresá un pH válido (0 a 14).';
    }
    if (a.resultado != 'conforme' && a.resultado != 'no_conforme') {
      return 'Elegí el resultado.';
    }
    if (a.resultado == 'no_conforme' && (a.accionTomada?.trim().isEmpty ?? true)) {
      return 'Indicá qué acción se tomó, ya que no cumple.';
    }
    if ((a.aspecto?.length ?? 0) > 200) return 'El aspecto es demasiado largo.';
    if ((a.accionTomada?.length ?? 0) > 300) return 'La acción tomada es demasiado larga.';
    if ((a.observaciones?.length ?? 0) > 300) return 'Las observaciones son demasiado largas.';
    return _ejecutar(() async {
      await _repo.registrarAnalisis(a);
    });
  }

  Future<String?> actualizarAnalisis(
    AnalisisCalidad a, {
    String? accionTomada,
    String? observaciones,
  }) async {
    if (!puedeEditar) return 'No tenés permiso para editar un análisis.';
    if ((accionTomada?.length ?? 0) > 300) return 'La acción tomada es demasiado larga.';
    if ((observaciones?.length ?? 0) > 300) return 'Las observaciones son demasiado largas.';
    return _ejecutar(
        () => _repo.actualizarAnalisis(a.id, accionTomada: accionTomada, observaciones: observaciones));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioCalidad catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('CalidadService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
