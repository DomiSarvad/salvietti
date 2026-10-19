import '../utils/texto.dart';

/// Búsqueda en memoria, para los buscadores que se usan escribiendo
/// ("tapa neg…"): en vez de preguntarle al servidor a cada letra (una ida y
/// vuelta por red por tecla, lo que hacía lentos todos los formularios), se
/// carga el catálogo una vez y se filtra acá, al instante.
///
/// El texto de cada elemento se normaliza (minúsculas, sin tildes) UNA vez al
/// armar el índice, no en cada tecla. Exige todas las palabras escritas, en
/// cualquier orden (igual que el buscador de Almacenes), y pone primero lo
/// que empieza con lo escrito.
class IndiceBusqueda<T> {
  final List<(T, String)> _entradas;

  IndiceBusqueda(Iterable<T> elementos, String Function(T) texto)
      : _entradas = [for (final e in elementos) (e, ' ${sinTildes(texto(e))}')];

  int get length => _entradas.length;

  List<T> buscar(String consulta, {int limite = 30, bool Function(T)? donde}) {
    final palabras = palabrasDe(consulta);
    final primero = <T>[], resto = <T>[];
    for (final (e, texto) in _entradas) {
      if (donde != null && !donde(e)) continue;
      if (!palabras.every(texto.contains)) continue;
      // Alguna palabra del elemento empieza con lo primero que se escribió.
      if (palabras.isNotEmpty && texto.contains(' ${palabras.first}')) {
        primero.add(e);
        if (primero.length >= limite) break;
      } else if (primero.length + resto.length < limite) {
        resto.add(e);
      }
    }
    return [...primero, ...resto].take(limite).toList();
  }

  static List<String> palabrasDe(String consulta) =>
      sinTildes(consulta.trim()).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
}

/// Un catálogo que se trae del servidor UNA vez y después se busca en
/// memoria. Se vuelve a pedir pasado [vigencia] (por si se dio de alta algo
/// mientras tanto) o con [invalidar]. Si dos búsquedas llegan juntas mientras
/// carga, comparten la misma carga.
class CatalogoLocal<T> {
  final Future<List<T>> Function() _cargar;
  final String Function(T) _texto;
  final Duration vigencia;

  CatalogoLocal(this._cargar, this._texto, {this.vigencia = const Duration(minutes: 5)});

  IndiceBusqueda<T>? _indice;
  DateTime? _cargadoEn;
  Future<IndiceBusqueda<T>>? _enCurso;

  Future<IndiceBusqueda<T>> _obtener() {
    final i = _indice;
    if (i != null && DateTime.now().difference(_cargadoEn!) < vigencia) return Future.value(i);
    return _enCurso ??= _cargar().then((lista) {
      _indice = IndiceBusqueda(lista, _texto);
      _cargadoEn = DateTime.now();
      return _indice!;
    }).whenComplete(() => _enCurso = null);
  }

  /// Para adelantar la carga al abrir un formulario, así la primera letra
  /// ya encuentra el catálogo en memoria. Si falla, se reintenta al buscar.
  void precargar() => _obtener().ignore();

  Future<List<T>> buscar(String consulta, {int limite = 30}) async =>
      (await _obtener()).buscar(consulta, limite: limite);

  void invalidar() => _indice = null;
}
