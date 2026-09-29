import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/informe_modelos.dart';
import '../repositories/informe_repository.dart';

/// Informe general de Producción: solo lectura, junta lo que otros módulos
/// ya registraron (Jarabes, Registro de salidas, Mermas). No conoce widgets.
class InformeService extends ChangeNotifier {
  InformeService(this._repo, this._usuario);

  final InformeRepository _repo;
  final Usuario _usuario;

  List<ResumenProduccion> resumen = [];

  bool cargando = true;
  String? error;

  bool get puedeVer => _usuario.puede(Modulo.informeProduccion, Accion.ver, reglaAnterior: false);

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
      resumen = await _repo.resumen();
      error = null;
    } catch (e) {
      error = 'No se pudo cargar el Informe. Revisá la conexión o que la '
          'migración v38 esté ejecutada.';
      if (kDebugMode) debugPrint('InformeService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<List<DetalleMermaArea>> mermaDe(ResumenProduccion r) {
    if (r.saborId == null) return Future.value(const []);
    return _repo.mermaDe(fecha: r.fecha, saborId: r.saborId!);
  }
}
