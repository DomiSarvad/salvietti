import 'package:flutter/foundation.dart';
import '../../../shared/busqueda_local.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/soda_modelos.dart';
import '../repositories/soda_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';

/// Reglas de Soda Cáustica: quién puede registrar una entrega y validación
/// de cantidades. El stock lo maneja el almacén propio (Módulo 1); esto
/// solo agrega el registro de a quién se le entregó, para la constancia.
/// No conoce widgets.
class SodaService extends ChangeNotifier {
  SodaService(this._repo, this._usuario);

  final SodaRepository _repo;
  final Usuario _usuario;

  List<EntregaSoda> entregas = [];

  bool cargando = true;
  String? error;

  bool _puede(String accion) => _usuario.puede(Modulo.sodaCaustica, accion, reglaAnterior: false);
  bool get puedeVer => _puede(Accion.ver);
  bool get puedeCrear => _puede(Accion.crear);

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
      entregas = await _repo.entregas();
      error = null;
    } catch (e) {
      error = 'No se pudo cargar Soda Cáustica. Revisá la conexión o que la '
          'migración v36 esté ejecutada.';
      if (kDebugMode) debugPrint('SodaService: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  // Se busca en memoria (CatalogoLocal): una consulta, no una por letra.
  late final _catItems =
      CatalogoLocal<ItemInventario>(_repo.items, (i) => '${i.codigo} ${i.detalle}');
  Future<List<ItemInventario>> buscarItems(String texto) => _catItems.buscar(texto);

  /// Devuelve el id de la entrega creada (para armar la constancia), o
  /// lanza con el mensaje de error ya en `error` — se usa desde el diálogo,
  /// que necesita el registro completo para el PDF.
  Future<String?> registrarEntrega({
    required ItemInventario? item,
    required double? cantidad,
    required String entregadoA,
    String? areaRecibe,
    String? motivo,
  }) async {
    if (!puedeCrear) return 'No tenés permiso para registrar entregas de Soda Cáustica.';
    if (item == null) return 'Elegí el ítem.';
    if (cantidad == null || cantidad.isNaN || cantidad <= 0) {
      return 'La cantidad debe ser mayor a cero.';
    }
    if (entregadoA.trim().length < 2) return 'Indicá a quién se le entrega.';
    if ((areaRecibe?.length ?? 0) > 80) return 'El área es demasiado larga.';
    if ((motivo?.length ?? 0) > 300) return 'El motivo es demasiado largo.';
    try {
      await _repo.registrarEntrega(
        itemId: item.id,
        cantidad: cantidad,
        entregadoA: entregadoA.trim(),
        areaRecibe: (areaRecibe?.trim().isEmpty ?? true) ? null : areaRecibe!.trim(),
        motivo: (motivo?.trim().isEmpty ?? true) ? null : motivo!.trim(),
      );
      await recargar();
      return null;
    } on ErrorNegocioSoda catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('SodaService: $e');
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

  List<EntregaSoda> get entregasFiltradas => filtro.aplicar(entregas,
      texto: (x) => <String?>[x.codigo, x.detalle, x.entregadoA, x.areaRecibe, x.motivo, x.responsableNombre].whereType<String>().join(' '),
      fecha: (x) => x.fechaHora);

  ReporteTabla reporte() => ReporteTabla(
        titulo: 'Entregas de Soda Cáustica',
        filtros: filtro.describir(),
        columnas: const ['Fecha', 'Código', 'Ítem', 'Cantidad', 'Unidad', 'Entregado a', 'Área', 'Motivo', 'Responsable'],
        filas: [
          for (final x in entregasFiltradas) [x.fechaHora, x.codigo, x.detalle, x.cantidad, x.unidad, x.entregadoA, x.areaRecibe, x.motivo, x.responsableNombre]
        ],
      );
}
