import 'package:flutter/foundation.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../../../utils/texto.dart';
import '../models/categoria_inv.dart';
import '../models/conteo_nuevo.dart';
import '../models/existencia_item.dart';
import '../models/unidad_medida.dart';
import '../repositories/inventario_repository.dart';

/// Una fila del balance: un ítem y lo que se escribió para él.
class FilaBalance {
  final ExistenciaItem item;
  final String categoriaRaiz;
  String unidadEntrada;
  String texto = '';

  FilaBalance(this.item, this.categoriaRaiz) : unidadEntrada = item.unidad;

  bool get vacia => texto.trim().isEmpty;

  double? get valor {
    final t = texto.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  bool get invalida => !vacia && (valor == null || valor! < 0);

  /// Lo escrito, pasado a la unidad del ítem (ej. gramos → kilos).
  double? get valorEnUnidadItem => valor == null
      ? null
      : UnidadMedida.convertir(valor!, de: unidadEntrada, a: item.unidad);

  double? get diferencia => valorEnUnidadItem == null
      ? null
      : valorEnUnidadItem! - item.cantidadSistema;

  /// Unidades en las que se puede escribir la cantidad (pesan en gramos lo
  /// que se controla en kilos, y en mililitros lo que se controla en litros).
  List<String> get unidadesPosibles {
    switch (item.unidad) {
      case 'KG':
        return const ['KG', 'GR'];
      case 'L':
        return const ['L', 'ML'];
      default:
        return [item.unidad];
    }
  }
}

/// Balance de insumos: conteo físico de todo un almacén en una sola pasada,
/// que reemplaza el balance del cuaderno. Guarda solo las filas que se
/// llenaron; el servidor calcula cada diferencia como ajuste.
class BalanceService extends ChangeNotifier {
  BalanceService(this._repo, this._usuario, this.almacenId);

  final InventarioRepository _repo;
  final Usuario _usuario;
  final String almacenId;

  List<FilaBalance> filas = [];
  String busqueda = '';
  bool cargando = true;
  bool guardando = false;
  String? error;

  bool get puedeEditar => _usuario.puede(Modulo.inventarioDe(almacenId), Accion.editar,
      reglaAnterior: false);

  Future<void> cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final resultados =
          await Future.wait([_repo.categorias(almacenId), _repo.existencias(almacenId)]);
      final categorias = resultados[0] as List<CategoriaInv>;
      final existencias = resultados[1] as List<ExistenciaItem>;
      filas = [
        for (final e in existencias) FilaBalance(e, _raiz(categorias, e.categoriaId)),
      ]..sort((a, b) {
          final c = a.categoriaRaiz.compareTo(b.categoriaRaiz);
          return c != 0 ? c : a.item.detalle.compareTo(b.item.detalle);
        });
    } catch (e) {
      error = 'No se pudo cargar el balance. Revisá la conexión.';
      if (kDebugMode) debugPrint('BalanceService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  String _raiz(List<CategoriaInv> categorias, int id) {
    CategoriaInv? actual = categorias.where((c) => c.id == id).firstOrNull;
    while (actual?.padreId != null) {
      actual = categorias.where((c) => c.id == actual!.padreId).firstOrNull;
    }
    return actual?.nombre ?? 'Sin categoría';
  }

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  List<FilaBalance> get visibles {
    final q = sinTildes(busqueda.trim());
    if (q.isEmpty) return filas;
    return filas
        .where((f) =>
            sinTildes(f.item.detalle).contains(q) || sinTildes(f.item.codigo).contains(q))
        .toList();
  }

  void escribir(FilaBalance fila, String texto) {
    fila.texto = texto;
    notifyListeners();
  }

  void cambiarUnidad(FilaBalance fila, String unidad) {
    fila.unidadEntrada = unidad;
    notifyListeners();
  }

  int get contados => filas.where((f) => !f.vacia && !f.invalida).length;
  int get invalidos => filas.where((f) => f.invalida).length;
  int get conDiferencia =>
      filas.where((f) => f.diferencia != null && f.diferencia!.abs() > 1e-9).length;

  /// Guarda las filas llenas. Devuelve null si salió bien, o el mensaje.
  Future<String?> guardar({String? nota}) async {
    if (!puedeEditar) return 'No tenés permiso para contar en este almacén.';
    if (invalidos > 0) return 'Hay valores inválidos: revisá las filas marcadas en rojo.';
    if (contados == 0) return 'Todavía no cargaste ninguna cantidad.';

    final texto = nota?.trim() ?? '';
    final observacion = texto.isEmpty ? 'Balance de insumos' : 'Balance de insumos · $texto';
    if (observacion.length > 300) return 'La nota es demasiado larga.';

    guardando = true;
    notifyListeners();
    try {
      await _repo.registrarConteos([
        for (final f in filas)
          if (!f.vacia)
            ConteoNuevo(
              itemId: f.item.itemId,
              almacenId: almacenId,
              cantidadReal: f.valorEnUnidadItem!,
              observaciones: observacion,
            ),
      ]);
      guardando = false;
      notifyListeners();
      return null;
    } catch (e) {
      guardando = false;
      notifyListeners();
      final t = e.toString().toLowerCase();
      if (t.contains('row-level security') || t.contains('permission denied')) {
        return 'No tenés permiso para hacer esto.';
      }
      return 'No se pudo guardar el balance. No se registró ningún conteo; intentá de nuevo.';
    }
  }
}
