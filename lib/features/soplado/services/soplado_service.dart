import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/soplado_modelos.dart';
import '../repositories/soplado_repository.dart';

/// Reglas del módulo de Soplado: quién puede iniciar/finalizar corridas,
/// validación de la matriz sabor × presentación (solo PET) y del cierre
/// (merma coherente con lo soplado y lo usado). No conoce widgets.
class SopladoService extends ChangeNotifier {
  SopladoService(this._repo, this._usuario);

  final SopladoRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Presentacion> presentaciones = [];
  List<CorridaSoplado> corridas = [];
  List<AvanceSoplado> avance = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.soplado, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);
  bool get puedeEditar => _puede(Accion.editar);

  List<CorridaSoplado> get enCurso =>
      corridas.where((c) => c.estado == EstadoCorrida.enCurso).toList();
  List<CorridaSoplado> get historial =>
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
        _repo.presentacionesPet(),
        _repo.corridas(),
        _repo.avance(),
      ]);
      sabores = r[0] as List<Sabor>;
      presentaciones = r[1] as List<Presentacion>;
      corridas = r[2] as List<CorridaSoplado>;
      avance = r[3] as List<AvanceSoplado>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Soplado. Revisá la conexión o que las '
          'migraciones v25 y v28 estén ejecutadas.';
      if (kDebugMode) debugPrint('SopladoService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  Future<Set<int>> presentacionesDe(int saborId) => _repo.presentacionesDe(saborId);
  Future<List<ItemPreforma>> buscarPreformas(String texto) => _repo.preformas(busqueda: texto);
  Future<List<Proveedor>> buscarProveedores(String texto) => _repo.proveedores(busqueda: texto);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> iniciarCorrida({
    required int? saborId,
    required int? presentacionId,
    int? itemPreformaId,
    int? proveedorId,
    String? lotePreforma,
  }) async {
    if (!puedeCrear) return 'No tenés permiso para registrar producción de Soplado.';
    if (saborId == null) return 'Elegí el sabor.';
    if (presentacionId == null) return 'Elegí la presentación.';
    if ((lotePreforma?.length ?? 0) > 40) return 'El lote de la preforma es demasiado largo.';
    return _ejecutar(() => _repo.iniciarCorrida(
        saborId: saborId,
        presentacionId: presentacionId,
        itemPreformaId: itemPreformaId,
        proveedorId: proveedorId,
        lotePreforma: (lotePreforma?.trim().isEmpty ?? true) ? null : lotePreforma!.trim()));
  }

  Future<String?> finalizarCorrida(CorridaSoplado c, FinalizarCorrida d) async {
    if (!puedeEditar) return 'No tenés permiso para finalizar una corrida.';
    if (c.estado != EstadoCorrida.enCurso) return 'Esa corrida ya se cerró.';
    if (d.botellasSopladas.isNaN || d.botellasSopladas < 0) {
      return 'La cantidad de botellas sopladas no puede ser negativa.';
    }
    if (d.preformasUsadas.isNaN || d.preformasUsadas < 0) {
      return 'Las preformas usadas no pueden ser negativas.';
    }
    if (d.mermaSoplado < 0 || d.mermaPreforma < 0 || d.mermaEtiquetado < 0) {
      return 'La merma no puede ser negativa.';
    }
    if (d.botellasEtiquetadas != null && d.botellasEtiquetadas! < 0) {
      return 'Las botellas etiquetadas no pueden ser negativas.';
    }
    if (d.mermaPreforma > d.preformasUsadas) {
      return 'No se pueden desechar más preformas de las que se usaron.';
    }
    if (d.mermaSoplado > d.botellasSopladas) {
      return 'La merma de soplado no puede ser mayor a lo soplado.';
    }
    final hayMerma = d.mermaSoplado > 0 || d.mermaPreforma > 0 || d.mermaEtiquetado > 0;
    if (hayMerma && (d.motivoMerma?.trim().isEmpty ?? true)) {
      return 'Indicá el motivo de la merma.';
    }
    if ((d.tiempoParadaMinutos ?? 0) > 0 && (d.motivoParada?.trim().isEmpty ?? true)) {
      return 'Indicá el motivo de la parada.';
    }
    return _ejecutar(() => _repo.finalizarCorrida(c.id, d));
  }

  Future<String?> anularCorrida(CorridaSoplado c, String motivo) async {
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
    } on ErrorNegocioSoplado catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('SopladoService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
