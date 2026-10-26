import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/mermas_modelos.dart';
import '../repositories/mermas_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';

/// Reglas de Mermas: quién puede registrar merma de cada área (además del
/// permiso genérico del módulo), causas válidas y validación de cantidades.
/// El servidor vuelve a validar todo esto; acá se evita el viaje si ya se
/// ve el error. No conoce widgets.
class MermasService extends ChangeNotifier {
  MermasService(this._repo, this._usuario);

  final MermasRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Presentacion> presentaciones = [];
  List<EventoMerma> consolidado = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.mermas, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);

  /// Qué áreas puede cargar el rol actual (espejo de `_mermas_area_de_rol`
  /// en el servidor, que es quien realmente decide).
  List<AreaMerma> get areasPermitidas {
    switch (_usuario.rol) {
      case 'jarabes':
      case 'ayudante_jarabes':
        return const [AreaMerma.jarabes];
      case 'control_calidad':
        return const [AreaMerma.calidad];
      case 'jefe_produccion':
      case 'gerente':
        return AreaMerma.values;
      default:
        return const [];
    }
  }

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
        _repo.consolidado(),
      ]);
      sabores = r[0] as List<Sabor>;
      presentaciones = r[1] as List<Presentacion>;
      consolidado = r[2] as List<EventoMerma>;
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Mermas. Revisá la conexión o que la '
          'migración v35 esté ejecutada.';
      if (kDebugMode) debugPrint('MermasService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  List<EventoMerma> get conAlerta => consolidado.where((e) => e.alerta).toList();

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> registrar({
    required AreaMerma? area,
    required int? saborId,
    required Map<String, double> causas,
    int? presentacionId,
    double? cantidadProducida,
    String? motivo,
  }) async {
    if (!puedeCrear) return 'No tenés permiso para registrar mermas.';
    if (area == null) return 'Elegí el área.';
    if (!areasPermitidas.contains(area)) return 'Tu rol no registra mermas de esa área.';
    if (saborId == null) return 'Elegí el sabor.';
    final validas = causas.entries.where((e) => e.value > 0).toList();
    if (validas.isEmpty) return 'Indicá al menos una causa con cantidad mayor a cero.';
    if ((cantidadProducida ?? 0) < 0) return 'Lo producido no puede ser negativo.';
    if ((motivo?.length ?? 0) > 300) return 'El motivo es demasiado largo.';
    try {
      await _repo.registrar(
        area: area.id,
        saborId: saborId,
        causas: [for (final e in validas) MapEntry(e.key, e.value)],
        presentacionId: presentacionId,
        cantidadProducida: cantidadProducida,
        motivo: (motivo?.trim().isEmpty ?? true) ? null : motivo!.trim(),
      );
      await recargar();
      return null;
    } on ErrorNegocioMermas catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('MermasService: $e');
      final t = e.toString().toLowerCase();
      if (t.contains('timeout') || t.contains('socket')) {
        return 'Sin conexión. No se hizo ningún cambio; intentá de nuevo.';
      }
      return 'No se pudo completar la operación.';
    }
  }

  // ------------------------------------------------- buscador y reporte

  /// Filtro del buscador (texto + Desde/Hasta): define qué se ve en la lista y
  /// qué sale en el reporte PDF/Excel ("lo que ves es lo que se imprime").
  FiltroLista filtro = const FiltroLista();

  void filtrar(FiltroLista f) {
    filtro = f;
    notifyListeners();
  }

  List<EventoMerma> get consolidadoFiltrado => filtro.aplicar(consolidado,
      texto: (x) => <String?>[x.area, x.sabor, x.presentacion, x.motivo].whereType<String>().join(' '),
      fecha: (x) => x.fecha);

  ReporteTabla reporte() => ReporteTabla(
        titulo: 'Eventos de merma',
        filtros: filtro.describir(),
        columnas: const ['Fecha', 'Área', 'Sabor', 'Presentación', 'Merma', 'Producido', '% merma', 'Alerta', 'Motivo'],
        filas: [
          for (final x in consolidadoFiltrado) [x.fecha, x.area, x.sabor, x.presentacion, x.totalMerma, x.producido, x.porcentaje, x.alerta ? 'Sí' : 'No', x.motivo]
        ],
      );
}
