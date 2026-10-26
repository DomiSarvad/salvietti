import '../../utils/formatters.dart';
import '../../utils/texto.dart';

/// Filtro de una lista: texto libre + rango de fechas (Desde/Hasta, ambos
/// incluidos, por día). Lo usan todas las pantallas con buscador; el mismo
/// filtro decide qué sale en el reporte PDF/Excel ("lo que ves es lo que se
/// imprime").
class FiltroLista {
  final String texto;
  final DateTime? desde;
  final DateTime? hasta;

  const FiltroLista({this.texto = '', this.desde, this.hasta});

  bool get activo => texto.trim().isNotEmpty || desde != null || hasta != null;

  FiltroLista conTexto(String t) => FiltroLista(texto: t, desde: desde, hasta: hasta);
  FiltroLista conDesde(DateTime? d) => FiltroLista(texto: texto, desde: d, hasta: hasta);
  FiltroLista conHasta(DateTime? h) => FiltroLista(texto: texto, desde: desde, hasta: h);

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Todas las palabras escritas, en cualquier orden, sin importar tildes ni
  /// mayúsculas (igual que el buscador de Almacenes).
  List<String> get _palabras =>
      sinTildes(texto.trim()).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

  bool cumpleFecha(DateTime? f) {
    if (desde == null && hasta == null) return true;
    if (f == null) return false;
    final d = _dia(f.toLocal());
    if (desde != null && d.isBefore(_dia(desde!))) return false;
    if (hasta != null && d.isAfter(_dia(hasta!))) return false;
    return true;
  }

  /// [texto] arma el texto donde se busca (nombre, código, responsable…);
  /// [fecha] la fecha del registro (si es null, el rango no se aplica).
  List<T> aplicar<T>(
    Iterable<T> items, {
    required String Function(T) texto,
    DateTime? Function(T)? fecha,
  }) {
    final palabras = _palabras;
    return [
      for (final it in items)
        if ((fecha == null || cumpleFecha(fecha(it))) &&
            (palabras.isEmpty || _contiene(sinTildes(texto(it)), palabras)))
          it
    ];
  }

  static bool _contiene(String t, List<String> palabras) => palabras.every(t.contains);

  /// Para el encabezado del reporte: qué filtros se aplicaron.
  String describir() {
    final partes = <String>[
      if (texto.trim().isNotEmpty) 'Búsqueda: "${texto.trim()}"',
      if (desde != null) 'Desde ${fmtFecha(desde)}',
      if (hasta != null) 'Hasta ${fmtFecha(hasta)}',
    ];
    return partes.isEmpty ? 'Sin filtros (todo)' : partes.join('   ·   ');
  }
}
