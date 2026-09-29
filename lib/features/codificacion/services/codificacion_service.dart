import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/codificacion_modelos.dart';
import '../repositories/codificacion_repository.dart';

/// Reglas del módulo de Codificación: quién puede iniciar/finalizar
/// corridas, validación de la matriz sabor × presentación y del cierre
/// (merma coherente, motivo obligatorio). No conoce widgets.
class CodificacionService extends ChangeNotifier {
  CodificacionService(this._repo, this._usuario);

  final CodificacionRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Presentacion> presentaciones = [];
  List<CorridaCodificacion> corridas = [];
  List<AvanceCodificacion> avance = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.codificacion, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeEditar => _puede(Accion.editar);

  List<CorridaCodificacion> get enCurso =>
      corridas.where((c) => c.estado == EstadoCorrida.enCurso).toList();
  List<CorridaCodificacion> get historial =>
      corridas.where((c) => c.estado != EstadoCorrida.enCurso).toList();

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
        _repo.corridas(),
        _repo.avance(),
      ]);
      sabores = r[0] as List<Sabor>;
      presentaciones = r[1] as List<Presentacion>;
      corridas = r[2] as List<CorridaCodificacion>;
      avance = r[3] as List<AvanceCodificacion>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Codificación. Revisá la conexión o que la '
          'migración v33 esté ejecutada.';
      if (kDebugMode) debugPrint('CodificacionService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<Set<int>> presentacionesDe(int saborId) => _repo.presentacionesDe(saborId);
  Future<List<CorridaLlenadoraRef>> corridasLlenadoraDe(int saborId) =>
      _repo.corridasLlenadoraDe(saborId);
  Future<List<ItemInventario>> buscarItems(String texto) => _repo.items(busqueda: texto);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> iniciarCorrida({
    required String? turno,
    required int? saborId,
    required int? presentacionId,
    int? corridaLlenadoraId,
    String? nLote,
    int? itemSolventeId,
    int? itemTintaId,
  }) async {
    if (!puedeCrear) return 'No tenés permiso para registrar producción de Codificación.';
    if (turno == null) return 'Elegí el turno.';
    if (saborId == null) return 'Elegí el sabor.';
    if (presentacionId == null) return 'Elegí la presentación.';
    if ((nLote?.length ?? 0) > 40) return 'El número de lote es demasiado largo.';
    return _ejecutar(() => _repo.iniciarCorrida(
        turno: turno,
        saborId: saborId,
        presentacionId: presentacionId,
        corridaLlenadoraId: corridaLlenadoraId,
        nLote: (nLote?.trim().isEmpty ?? true) ? null : nLote!.trim(),
        itemSolventeId: itemSolventeId,
        itemTintaId: itemTintaId));
  }

  Future<String?> finalizarCorrida(CorridaCodificacion c, FinalizarCorridaCodificacion d) async {
    if (!puedeEditar) return 'No tenés permiso para finalizar una corrida.';
    if (c.estado != EstadoCorrida.enCurso) return 'Esa corrida ya se cerró.';
    if (d.botellasCodificadas.isNaN || d.botellasCodificadas < 0) {
      return 'La cantidad de botellas codificadas no puede ser negativa.';
    }
    if (d.botellasMalTapadas < 0 || d.tapasMalTapadas < 0 || d.impurezas < 0
        || d.solventeUsado < 0 || d.tintaUsada < 0) {
      return 'Ningún valor puede ser negativo.';
    }
    if (d.botellasMalTapadas > d.botellasCodificadas
        || d.tapasMalTapadas > d.botellasCodificadas
        || d.impurezas > d.botellasCodificadas) {
      return 'La merma no puede ser mayor a lo codificado.';
    }
    final hayMerma = d.botellasMalTapadas > 0 || d.tapasMalTapadas > 0 || d.impurezas > 0;
    if (hayMerma && (d.motivoMerma?.trim().isEmpty ?? true)) {
      return 'Indicá el motivo de la merma.';
    }
    return _ejecutar(() => _repo.finalizarCorrida(c.id, d));
  }

  Future<String?> anularCorrida(CorridaCodificacion c, String motivo) async {
    if (!puedeEditar) return 'No tenés permiso para anular una corrida.';
    if (c.estado != EstadoCorrida.enCurso) return 'Solo se anula una corrida en curso.';
    final t = motivo.trim();
    if (t.length < 3) return 'Escribí el motivo (mínimo 3 caracteres).';
    return _ejecutar(() => _repo.anularCorrida(c.id, t));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioCodificacion catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('CodificacionService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
