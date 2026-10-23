import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/aviso_campana.dart';
import '../repositories/campana_repository.dart';

/// La campana flotante: junta en un solo lugar lo que cada persona tiene
/// pendiente.
///  - Quien aprueba (Gerente): pedidos de compra, solicitudes y recetas que
///    esperan su confirmación.
///  - Calidad / Jefe de Producción: recetas que esperan SU visto bueno.
///  - Todos: las respuestas a lo que mandaron (aprobado/rechazado), hasta que
///    las miran.
/// Se actualiza sola (Realtime) y, por las dudas, cada 2 minutos.
class CampanaService extends ChangeNotifier {
  CampanaService(this._repo, this._usuario, {DateTime Function()? ahora})
      : _ahora = ahora ?? DateTime.now;

  final CampanaRepository _repo;
  final Usuario _usuario;
  final DateTime Function() _ahora;

  /// Hasta cuántos días atrás se avisan las respuestas no vistas.
  static const ventanaRespuestas = Duration(days: 14);

  List<AvisoCampana> avisos = [];
  List<RespuestaPropia> _respuestasNoVistas = [];

  Suscripcion? _suscripcion;
  Timer? _cada2min;
  Timer? _debounce;
  bool _cerrado = false;

  bool _puede(String modulo, String accion) => _usuario.puede(modulo, accion, reglaAnterior: false);

  bool get puedeCrearSolicitud => _puede(Modulo.solicitudes, Accion.crear);

  int get total => avisos.fold(0, (s, a) => s + a.cantidad);

  void iniciar() {
    cargar();
    _suscripcion = _repo.escucharCambios(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), cargar);
    });
    _cada2min = Timer.periodic(const Duration(minutes: 2), (_) => cargar());
  }

  @override
  void dispose() {
    _cerrado = true;
    _suscripcion?.cancelar();
    _cada2min?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  /// Cada consulta falla sola sin tumbar las demás (ej. sin la migración
  /// v43, o un rol que no ve cierta tabla).
  Future<int> _seguro(Future<int> Function() f) async {
    try {
      return await f();
    } catch (e) {
      if (kDebugMode) debugPrint('CampanaService: $e');
      return 0;
    }
  }

  Future<void> cargar() async {
    final esGerente = _usuario.rol == Rol.gerente;
    final r = await Future.wait([
      _puede(Modulo.compras, Accion.aprobar) ? _seguro(_repo.comprasPendientes) : Future.value(0),
      _puede(Modulo.aprobaciones, Accion.aprobar) ? _seguro(_repo.solicitudesPendientes) : Future.value(0),
      esGerente && _puede(Modulo.recetas, Accion.aprobar)
          ? _seguro(() => _repo.recetasEsperando(falta: 'gerente'))
          : Future.value(0),
      _usuario.rol == Rol.controlCalidad && _puede(Modulo.recetas, Accion.aprobar)
          ? _seguro(() => _repo.recetasEsperando(falta: 'calidad'))
          : Future.value(0),
      _usuario.rol == Rol.jefeProduccion && _puede(Modulo.recetas, Accion.aprobar)
          ? _seguro(() => _repo.recetasEsperando(falta: 'produccion'))
          : Future.value(0),
    ]);
    List<RespuestaPropia> respuestas = const [];
    try {
      final vistos = _repo.vistos(_usuario.id);
      respuestas = (await _repo.respuestasPropias(_usuario.id, _ahora().subtract(ventanaRespuestas)))
          .where((x) => !vistos.contains(x.clave))
          .toList();
    } catch (_) {}
    if (_cerrado) return;

    _respuestasNoVistas = respuestas;
    final solicitudesResp = respuestas.where((x) => x.tipo == 'solicitud').length;
    final comprasResp = respuestas.where((x) => x.tipo == 'compra').length;
    avisos = [
      if (r[0] > 0)
        AvisoCampana(
            id: 'compras_por_aprobar',
            titulo: 'Pedidos de compra',
            detalle: 'Almacén espera tu aprobación para comprar',
            cantidad: r[0],
            ruta: 'compras',
            icono: 'compras'),
      if (r[1] > 0)
        AvisoCampana(
            id: 'solicitudes_por_resolver',
            titulo: 'Solicitudes y preguntas',
            detalle: 'Pedidos del personal (nuevos sabores, autorizaciones…)',
            cantidad: r[1],
            ruta: 'solicitudes',
            icono: 'solicitudes'),
      if (r[2] > 0)
        AvisoCampana(
            id: 'recetas_gerente',
            titulo: 'Recetas por confirmar',
            detalle: 'Ya tienen el visto bueno de Calidad y Producción',
            cantidad: r[2],
            ruta: 'jarabes',
            icono: 'recetas'),
      if (r[3] + r[4] > 0)
        AvisoCampana(
            id: 'recetas_visto_bueno',
            titulo: 'Recetas por aprobar',
            detalle: 'Cambios de receta que esperan tu visto bueno',
            cantidad: r[3] + r[4],
            ruta: 'jarabes',
            icono: 'recetas'),
      if (comprasResp > 0)
        AvisoCampana(
            id: 'respuestas_compras',
            titulo: 'Respuestas a tus pedidos de compra',
            detalle: 'El Gerente aprobó o rechazó',
            cantidad: comprasResp,
            ruta: 'compras',
            icono: 'respuesta',
            seMarcaVisto: true),
      if (solicitudesResp > 0)
        AvisoCampana(
            id: 'respuestas_solicitudes',
            titulo: 'Respuestas a tus solicitudes',
            detalle: 'Gerencia respondió',
            cantidad: solicitudesResp,
            ruta: 'solicitudes',
            icono: 'respuesta',
            seMarcaVisto: true),
    ];
    notifyListeners();
  }

  /// Al abrir un aviso de respuestas: deja de contarlas.
  Future<void> abrir(AvisoCampana a) async {
    if (!a.seMarcaVisto) return;
    final tipo = a.id == 'respuestas_compras' ? 'compra' : 'solicitud';
    await _repo.marcarVistos(
        _usuario.id, [for (final x in _respuestasNoVistas) if (x.tipo == tipo) x.clave]);
    await cargar();
  }
}
