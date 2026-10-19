import 'package:flutter/foundation.dart';
import '../../../shared/busqueda_local.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/llenadora_modelos.dart';
import '../repositories/llenadora_repository.dart';

/// Reglas del módulo de Llenadora: quién puede iniciar/finalizar corridas,
/// validación de la matriz sabor × presentación y del cierre (merma
/// coherente, motivo obligatorio). No conoce widgets.
class LlenadoraService extends ChangeNotifier {
  LlenadoraService(this._repo, this._usuario);

  final LlenadoraRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Presentacion> presentaciones = [];
  List<CorridaLlenadora> corridas = [];
  List<AvanceLlenadora> avance = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.llenado, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeEditar => _puede(Accion.editar);

  List<CorridaLlenadora> get enCurso =>
      corridas.where((c) => c.estado == EstadoCorrida.enCurso).toList();
  List<CorridaLlenadora> get historial =>
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
      corridas = r[2] as List<CorridaLlenadora>;
      avance = r[3] as List<AvanceLlenadora>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Llenadora. Revisá la conexión o que la '
          'migración v32 esté ejecutada.';
      if (kDebugMode) debugPrint('LlenadoraService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<Set<int>> presentacionesDe(int saborId) => _repo.presentacionesDe(saborId);
  Future<List<PreparadoJarabes>> preparadosDe(int saborId) => _repo.preparadosDe(saborId);
  // Se busca en memoria (CatalogoLocal): una consulta, no una por letra.
  late final _catTapas =
      CatalogoLocal<ItemInventario>(_repo.tapas, (i) => '${i.codigo} ${i.detalle}');
  Future<List<ItemInventario>> buscarTapas(String texto) => _catTapas.buscar(texto);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> iniciarCorrida({
    required String? turno,
    required int? saborId,
    required int? presentacionId,
    int? preparadoId,
    String? nLotePreparado,
    String? tanque,
    int? itemTapaId,
  }) async {
    if (!puedeCrear) return 'No tenés permiso para registrar producción de Llenadora.';
    if (turno == null) return 'Elegí el turno.';
    if (saborId == null) return 'Elegí el sabor.';
    if (presentacionId == null) return 'Elegí la presentación.';
    if ((nLotePreparado?.length ?? 0) > 40) return 'El lote es demasiado largo.';
    if ((tanque?.length ?? 0) > 40) return 'El tanque es demasiado largo.';
    return _ejecutar(() => _repo.iniciarCorrida(
        turno: turno,
        saborId: saborId,
        presentacionId: presentacionId,
        preparadoId: preparadoId,
        nLotePreparado: (nLotePreparado?.trim().isEmpty ?? true) ? null : nLotePreparado!.trim(),
        tanque: (tanque?.trim().isEmpty ?? true) ? null : tanque!.trim(),
        itemTapaId: itemTapaId));
  }

  Future<String?> finalizarCorrida(CorridaLlenadora c, FinalizarCorridaLlenadora d) async {
    if (!puedeEditar) return 'No tenés permiso para finalizar una corrida.';
    if (c.estado != EstadoCorrida.enCurso) return 'Esa corrida ya se cerró.';
    if (d.botellasLlenadas.isNaN || d.botellasLlenadas < 0) {
      return 'La cantidad de botellas llenadas no puede ser negativa.';
    }
    if (d.botellasDesechadas < 0 || d.tapasUsadas < 0 || d.tapasDesechadas < 0 || d.rebalse < 0) {
      return 'La merma no puede ser negativa.';
    }
    if (d.botellasDesechadas > d.botellasLlenadas) {
      return 'No se pueden desechar más botellas de las que se llenaron.';
    }
    if (d.tapasDesechadas > d.tapasUsadas) {
      return 'No se pueden desechar más tapas de las que se usaron.';
    }
    final hayMerma = d.botellasDesechadas > 0 || d.tapasDesechadas > 0 || d.rebalse > 0;
    if (hayMerma && (d.motivoMerma?.trim().isEmpty ?? true)) {
      return 'Indicá el motivo de la merma.';
    }
    return _ejecutar(() => _repo.finalizarCorrida(c.id, d));
  }

  Future<String?> anularCorrida(CorridaLlenadora c, String motivo) async {
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
    } on ErrorNegocioLlenadora catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('LlenadoraService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
