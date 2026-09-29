import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/solicitud.dart';
import '../repositories/solicitudes_repository.dart';

enum BandejaSolicitudes {
  mias('Mis solicitudes'),
  porAprobar('Por aprobar'),
  resueltas('Resueltas');

  final String etiqueta;
  const BandejaSolicitudes(this.etiqueta);
}

/// Reglas de las solicitudes a Gerencia: quién puede crear, quién aprueba,
/// validación del formulario y agrupado en bandejas. No conoce widgets.
class SolicitudesService extends ChangeNotifier {
  SolicitudesService(this._repo, this._usuario);

  final SolicitudesRepository _repo;
  final Usuario _usuario;

  List<Solicitud> solicitudes = [];
  BandejaSolicitudes bandeja = BandejaSolicitudes.mias;
  bool cargando = true;
  String? error;

  bool _puede(String modulo, String accion) =>
      _usuario.puede(modulo, accion, reglaAnterior: false);

  bool get puedeVer => _puede(Modulo.solicitudes, Accion.ver);
  bool get puedeCrear => _puede(Modulo.solicitudes, Accion.crear);
  bool get puedeAprobar => _puede(Modulo.aprobaciones, Accion.aprobar);

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    bandeja = puedeAprobar ? BandejaSolicitudes.porAprobar : BandejaSolicitudes.mias;
    notifyListeners();
    if (!puedeVer) {
      cargando = false;
      notifyListeners();
      return;
    }
    await recargar();
  }

  Future<void> recargar() async {
    try {
      solicitudes = await _repo.solicitudes();
      error = null;
    } catch (e) {
      error = 'No se pudieron cargar las solicitudes. Revisá la conexión o que '
          'la migración v24 esté ejecutada.';
      if (kDebugMode) debugPrint('SolicitudesService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  void elegirBandeja(BandejaSolicitudes b) {
    bandeja = b;
    notifyListeners();
  }

  List<Solicitud> get visibles {
    switch (bandeja) {
      case BandejaSolicitudes.mias:
        return solicitudes.where((s) => s.solicitanteId == _usuario.id).toList();
      case BandejaSolicitudes.porAprobar:
        return solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).toList();
      case BandejaSolicitudes.resueltas:
        return solicitudes.where((s) => s.estado != EstadoSolicitud.pendiente).toList();
    }
  }

  int get pendientesDeAprobar =>
      solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).length;

  Future<List<ItemReferencia>> buscarItems(String texto) => _repo.items(busqueda: texto);

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> crear(SolicitudNueva s) async {
    if (!puedeCrear) return 'No tenés permiso para hacer solicitudes.';
    final asunto = s.asunto.trim();
    if (asunto.length < 3) return 'Escribí el asunto (mínimo 3 caracteres).';
    if (asunto.length > 120) return 'El asunto es demasiado largo.';
    if ((s.detalle?.length ?? 0) > 500) return 'El detalle es demasiado largo.';
    if (!TipoSolicitud.todos.contains(s.tipo)) return 'Elegí el tipo de solicitud.';
    if (s.cantidadSugerida != null && s.cantidadSugerida! <= 0) {
      return 'La cantidad debe ser mayor a cero.';
    }
    return _ejecutar(() => _repo.crear(SolicitudNueva(
          tipo: s.tipo,
          asunto: asunto,
          detalle: (s.detalle?.trim().isEmpty ?? true) ? null : s.detalle!.trim(),
          itemId: s.itemId,
          cantidadSugerida: s.cantidadSugerida,
        )));
  }

  Future<String?> aprobar(Solicitud s, {String? respuesta}) => _resolver(s, true, respuesta);

  Future<String?> rechazar(Solicitud s, String respuesta) {
    if (respuesta.trim().isEmpty) return Future.value('Explicá el motivo del rechazo.');
    return _resolver(s, false, respuesta);
  }

  Future<String?> _resolver(Solicitud s, bool aprobar, String? respuesta) async {
    if (!puedeAprobar) return 'No tenés permiso para resolver solicitudes.';
    if (s.estado != EstadoSolicitud.pendiente) return 'Esta solicitud ya fue resuelta.';
    if ((respuesta?.length ?? 0) > 500) return 'La respuesta es demasiado larga.';
    return _ejecutar(() => _repo.resolver(s.id, aprobar: aprobar, respuesta: respuesta?.trim()));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioSolicitud catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('SolicitudesService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }
}
