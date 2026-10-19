import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/presencia.dart';
import '../repositories/presencia_repository.dart';

/// Presencia de las áreas: cada app avisa cada minuto que sigue conectada (y
/// cuántos registros tiene sin subir), y lee el estado de las demás. Sirve
/// para que, por ejemplo, Jarabes sepa que Soplado está sin internet y que
/// el avance de Soplado que ve puede estar atrasado — el sistema no puede
/// mostrar lo que Soplado guardó en su compu, pero sí avisar que existe.
///
/// No usa Realtime a propósito: un latido por persona por minuto, reenviado
/// a todas las demás, gastaría la cuota de mensajes de Supabase. Se consulta
/// cada minuto, que para este aviso alcanza.
///
/// Vive toda la sesión de la app (provider en `main.dart`), no por pantalla.
class PresenciaService extends ChangeNotifier {
  PresenciaService(
    this._repo, {
    required int Function() pendientes,
    required String? Function() usuarioActual,
    required bool Function() hayRed,
    Listenable? cambios,
    DateTime Function()? ahora,
  })  : _pendientes = pendientes,
        _usuarioActual = usuarioActual,
        _hayRed = hayRed,
        _cambios = cambios,
        _ahora = ahora ?? DateTime.now;

  final PresenciaRepository _repo;
  final int Function() _pendientes;
  final String? Function() _usuarioActual;
  final bool Function() _hayRed;
  final Listenable? _cambios;
  final DateTime Function() _ahora;

  static const intervalo = Duration(minutes: 1);

  /// Sin señal hace más que esto (3 latidos perdidos) = probablemente sin
  /// internet. Menos sería falsa alarma por un corte de segundos.
  static const umbralSinSenal = Duration(minutes: 3);

  List<PresenciaUsuario> usuarios = [];
  DateTime? _leidoEn; // cuándo se leyó `usuarios` (reloj local, solo para sumar)

  Timer? _timer;
  Timer? _pronto;
  int? _pendientesEnviados;
  DateTime? _ultimoLatido;
  bool _cerrado = false;

  void iniciar() {
    _tick();
    _timer = Timer.periodic(intervalo, (_) => _tick());
    _cambios?.addListener(_alCambiar);
  }

  @override
  void dispose() {
    _cerrado = true;
    _timer?.cancel();
    _pronto?.cancel();
    _cambios?.removeListener(_alCambiar);
    super.dispose();
  }

  Future<void> _tick() async {
    await latido();
    await refrescar();
  }

  @visibleForTesting
  Future<void> latido() async {
    if (_usuarioActual() == null) return;
    final p = _pendientes();
    try {
      await _repo.latido(p);
      _pendientesEnviados = p;
      _ultimoLatido = _ahora();
    } catch (_) {
      // Sin internet: justamente lo que las demás áreas van a notar.
    }
  }

  @visibleForTesting
  Future<void> refrescar() async {
    if (_usuarioActual() == null) {
      usuarios = [];
    } else {
      try {
        usuarios = await _repo.recientes();
        _leidoEn = _ahora();
      } catch (_) {
        // Se queda con lo último leído; sin red los avisos no se muestran igual.
      }
    }
    if (!_cerrado) notifyListeners();
  }

  /// Cuando cambia la sincronización: si cambió la cantidad sin subir, o
  /// volvió la red después de un rato, avisa enseguida (sin esperar al
  /// próximo minuto), así las demás áreas dejan de ver la alerta al toque.
  void _alCambiar() {
    if (_usuarioActual() == null) return;
    final cambiaronPendientes = _pendientes() != _pendientesEnviados;
    final ultimo = _ultimoLatido;
    final atrasado = _hayRed() && (ultimo == null || _ahora().difference(ultimo) > intervalo);
    if (!cambiaronPendientes && !atrasado) return;
    _pronto?.cancel();
    _pronto = Timer(const Duration(seconds: 2), _tick);
  }

  /// Avisos sobre las áreas de [roles] (sin contar al propio usuario): quién
  /// está sin señal, y quién tiene registros sin subir. Vacío si este mismo
  /// dispositivo está sin red — en ese caso lo que se sabe de los demás es
  /// viejo, y el aviso de "sin conexión" propio ya está en la barra.
  List<AvisoArea> avisosDe(Iterable<String> roles) {
    if (!_hayRed()) return const [];
    final yo = _usuarioActual();
    final leido = _leidoEn;
    final transcurrido = leido == null ? 0 : _ahora().difference(leido).inSeconds;
    final avisos = <AvisoArea>[];
    for (final u in usuarios) {
      if (!roles.contains(u.rol) || u.usuarioId == yo || !u.activa) continue;
      final sinSenal = u.segundosSinSenal + transcurrido > umbralSinSenal.inSeconds;
      if (sinSenal) {
        avisos.add(AvisoArea(
            rol: u.rol, nombre: u.nombre, tipo: TipoAvisoArea.sinSenal,
            ultimaSenal: u.ultimaSenal, pendientes: u.pendientes));
      } else if (u.pendientes > 0) {
        avisos.add(AvisoArea(
            rol: u.rol, nombre: u.nombre, tipo: TipoAvisoArea.pendientes,
            ultimaSenal: u.ultimaSenal, pendientes: u.pendientes));
      }
    }
    return avisos;
  }
}
