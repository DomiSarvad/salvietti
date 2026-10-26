import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../models/informe_modelos.dart';
import '../repositories/informe_repository.dart';

/// Totales de lo que se está mirando (lo filtrado), para el encabezado.
class TotalesInforme {
  final int dias; // días con algo comparable
  final DateTime? desde;
  final DateTime? hasta;
  final double esperadas;
  final double producidas;
  final int conDesvio;
  const TotalesInforme({
    required this.dias,
    this.desde,
    this.hasta,
    required this.esperadas,
    required this.producidas,
    required this.conDesvio,
  });

  /// Desviación total de lo producido sobre lo esperado (null sin esperado).
  double? get desviacion => esperadas <= 0 ? null : (producidas - esperadas) * 100 / esperadas;
}

/// Informe general de Producción: solo lectura, junta lo que otros módulos
/// ya registraron (Jarabes, Registro de salidas, Mermas). No conoce widgets.
class InformeService extends ChangeNotifier {
  InformeService(this._repo, this._usuario);

  final InformeRepository _repo;
  final Usuario _usuario;

  List<ResumenProduccion> resumen = [];

  bool cargando = true;
  String? error;

  /// Buscador común (sabor) + Desde/Hasta.
  FiltroLista filtro = const FiltroLista();

  /// Solo las filas cuya desviación pasa del 3 % (lo que hay que mirar).
  bool soloDesvio = false;

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
      // Del más reciente al más antiguo (y por sabor dentro del día), sin
      // depender del orden en que llegue del servidor.
      resumen = [...await _repo.resumen()]..sort((a, b) {
          final f = b.fecha.compareTo(a.fecha);
          return f != 0 ? f : a.sabor.compareTo(b.sabor);
        });
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

  void filtrar(FiltroLista f) {
    filtro = f;
    notifyListeners();
  }

  void alternarSoloDesvio() {
    soloDesvio = !soloDesvio;
    notifyListeners();
  }

  bool get hayFiltros => filtro.activo || soloDesvio;

  List<ResumenProduccion> get filtrados => filtro
      .aplicar(resumen, texto: (r) => r.sabor, fecha: (r) => r.fecha)
      .where((r) => !soloDesvio || r.alertaDesviacion)
      .toList();

  /// Lo filtrado agrupado por día, en el mismo orden (más reciente primero).
  List<(DateTime, List<ResumenProduccion>)> get porDia {
    final grupos = <(DateTime, List<ResumenProduccion>)>[];
    for (final r in filtrados) {
      final d = DateTime(r.fecha.year, r.fecha.month, r.fecha.day);
      if (grupos.isEmpty || grupos.last.$1 != d) grupos.add((d, []));
      grupos.last.$2.add(r);
    }
    return grupos;
  }

  /// Suma de lo que se ve en la lista, pero solo de las filas que se pueden
  /// comparar (tienen esperado Y producido): un día con la producción todavía
  /// sin cargar sumaba lo esperado contra 0 y deformaba la desviación total.
  TotalesInforme get totales {
    final fs = filtrados
        .where((r) => (r.cajasEsperadas ?? 0) > 0 && r.cajasProducidas != null)
        .toList();
    final dias = [for (final r in fs) DateTime(r.fecha.year, r.fecha.month, r.fecha.day)]..sort();
    return TotalesInforme(
      dias: dias.toSet().length,
      desde: dias.isEmpty ? null : dias.first,
      hasta: dias.isEmpty ? null : dias.last,
      esperadas: fs.fold(0.0, (s, r) => s + r.cajasEsperadas!),
      producidas: fs.fold(0.0, (s, r) => s + r.cajasProducidas!),
      conDesvio: filtrados.where((r) => r.alertaDesviacion).length,
    );
  }

  Future<List<DetalleMermaArea>> mermaDe(ResumenProduccion r) {
    if (r.saborId == null) return Future.value(const []);
    return _repo.mermaDe(fecha: r.fecha, saborId: r.saborId!);
  }
}
