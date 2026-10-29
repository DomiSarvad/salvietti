import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/busqueda_local.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/jarabes_modelos.dart';
import '../repositories/jarabes_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';

/// Reglas de Recetas y producción de Jarabes: quién propone y quién aprueba
/// una receta, verificación de insumos antes de iniciar un preparado, y el
/// cierre con Brix. No conoce widgets.
class JarabesService extends ChangeNotifier {
  JarabesService(this._repo, this._usuario);

  final JarabesRepository _repo;
  final Usuario _usuario;

  List<Sabor> sabores = [];
  List<Preparado> preparados = [];
  List<RecetaPropuesta> recetasPendientes = [];
  List<AvanceSopladoLite> avanceSoplado = [];

  bool cargando = true;
  String? error;

  bool _puede(String modulo, String accion) =>
      _usuario.puede(modulo, accion, reglaAnterior: false);

  bool get puedeVerProduccion => _puede(Modulo.jarabesProduccion, Accion.ver);
  bool get puedeIniciar => _puede(Modulo.jarabesProduccion, Accion.crear);
  bool get puedeFinalizar => _puede(Modulo.jarabesProduccion, Accion.editar);
  bool get puedeProponerReceta => _puede(Modulo.recetas, Accion.crear);

  /// Puede VER la bandeja de recetas por resolver: cualquiera de los tres
  /// roles del proceso (alcanza con el permiso general de aprobar).
  bool get puedeAprobarReceta => _puede(Modulo.recetas, Accion.aprobar);

  /// El cambio de receta lo aprueban Calidad Y Producción por separado, y
  /// recién con las dos el Gerente la activa con su clave (sección 7 del
  /// md). Cada visto bueno es exclusivo de su rol.
  bool get puedeAprobarComoCalidad =>
      _usuario.rol == 'control_calidad' && puedeAprobarReceta;
  bool get puedeAprobarComoProduccion =>
      _usuario.rol == 'jefe_produccion' && puedeAprobarReceta;
  bool get puedeConfirmarComoGerente => _usuario.rol == 'gerente' && puedeAprobarReceta;

  List<Preparado> get enCurso =>
      preparados.where((p) => p.estado == EstadoPreparado.enCurso).toList();

  /// Todos los preparados de ese día (cualquier estado), del más temprano al último.
  List<Preparado> preparadosDelDia(DateTime dia) => preparados
      .where((p) => p.fecha.year == dia.year && p.fecha.month == dia.month && p.fecha.day == dia.day)
      .toList()
    ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));
  List<Preparado> get historial =>
      preparados.where((p) => p.estado != EstadoPreparado.enCurso).toList();

  Suscripcion? _suscripcion;
  Timer? _recargaPendiente;
  bool _cerrado = false;

  @override
  void dispose() {
    _cerrado = true;
    _suscripcion?.cancelar();
    _recargaPendiente?.cancel();
    super.dispose();
  }

  /// Tiempo real: cuando otra persona inicia/finaliza un preparado, resuelve
  /// una receta, o Soplado cierra una corrida, la pantalla se actualiza sola
  /// (sin spinner). Varios cambios seguidos se juntan en una sola recarga.
  void _escucharCambios() {
    _suscripcion ??= _repo.escucharCambios(() {
      _recargaPendiente?.cancel();
      _recargaPendiente = Timer(const Duration(milliseconds: 400), () => _cargar(silencioso: true));
    });
  }

  Future<void> iniciar() => _cargar(silencioso: false);

  Future<void> _cargar({required bool silencioso}) async {
    if (!silencioso) {
      cargando = true;
      error = null;
      notifyListeners();
    }
    if (!puedeVerProduccion) {
      cargando = false;
      notifyListeners();
      return;
    }
    _escucharCambios();
    try {
      final r = await Future.wait([
        _repo.sabores(),
        _repo.preparados(),
        _repo.avanceSoplado(),
        puedeAprobarReceta ? _repo.recetasPendientes() : Future.value(<RecetaPropuesta>[]),
      ]);
      sabores = r[0] as List<Sabor>;
      preparados = r[1] as List<Preparado>;
      avanceSoplado = r[2] as List<AvanceSopladoLite>;
      recetasPendientes = r[3] as List<RecetaPropuesta>;
      error = null;
    } catch (e) {
      // Una recarga en segundo plano que falla no tapa la pantalla con un
      // error: se siguen viendo los datos que ya había.
      if (!silencioso) {
        error = 'No se pudo cargar Jarabes. Revisá la conexión o que la '
            'migración v26 esté ejecutada.';
      }
      if (kDebugMode) debugPrint('JarabesService: $e');
    }
    if (_cerrado) return; // la pantalla se cerró mientras cargaba
    cargando = false;
    notifyListeners();
  }

  Future<void> recargar() => iniciar();

  // Se busca en memoria (CatalogoLocal): una consulta, no una por letra.
  late final _catItems =
      CatalogoLocal<ItemJarabes>(_repo.itemsJarabes, (i) => '${i.codigo} ${i.detalle}');
  Future<List<ItemJarabes>> buscarItems(String texto) => _catItems.buscar(texto);

  /// Todo el catálogo del almacén de Jarabes (para armar una receta). Antes
  /// salía de `buscarItems('')`, que el servidor cortaba en 30 ítems.
  Future<List<ItemJarabes>> catalogoItems() => _repo.itemsJarabes();
  Future<List<ItemReceta>> recetaVigente(int saborId) => _repo.recetaVigente(saborId);

  Future<List<VerificacionInsumo>> verificarInsumos(int saborId, double cantidad) =>
      _repo.verificarInsumos(saborId, cantidad);

  // -------------------------------------------------------------- recetas

  Future<String?> proponerReceta(int? saborId, Map<int, double> items) async {
    if (!puedeProponerReceta) return 'No tenés permiso para proponer recetas.';
    if (saborId == null) return 'Elegí el sabor.';
    if (items.isEmpty) return 'Agregá al menos un insumo.';
    if (items.values.any((c) => c.isNaN || c <= 0)) {
      return 'Cada insumo necesita una cantidad mayor a cero.';
    }
    return _ejecutar(() async {
      await _repo.recetaCrear(saborId, items);
    });
  }

  Future<String?> aprobarComoCalidad(RecetaPropuesta r) async {
    if (!puedeAprobarComoCalidad) return 'Este visto bueno lo da Control de Calidad.';
    if (r.estado != EstadoReceta.propuesta) return 'Esta receta ya fue resuelta.';
    if (r.tieneVistoBuenoCalidad) return 'Calidad ya dio su visto bueno a esta receta.';
    return _ejecutar(() => _repo.recetaAprobarCalidad(r.id));
  }

  Future<String?> aprobarComoProduccion(RecetaPropuesta r) async {
    if (!puedeAprobarComoProduccion) return 'Este visto bueno lo da Jefe de Producción.';
    if (r.estado != EstadoReceta.propuesta) return 'Esta receta ya fue resuelta.';
    if (r.tieneVistoBuenoProduccion) return 'Producción ya dio su visto bueno a esta receta.';
    return _ejecutar(() => _repo.recetaAprobarProduccion(r.id));
  }

  /// Confirma y activa la receta. El Gerente reingresa su clave acá: no
  /// alcanza con tener la sesión abierta, es una re-confirmación a
  /// propósito, porque afecta a todo el sistema.
  Future<String?> confirmarComoGerente(RecetaPropuesta r, String clave) async {
    if (!puedeConfirmarComoGerente) return 'Solo el Gerente confirma el cambio de receta.';
    if (r.estado != EstadoReceta.propuesta) return 'Esta receta ya fue resuelta.';
    if (!r.tieneVistoBuenoCalidad) return 'Todavía falta el visto bueno de Control de Calidad.';
    if (!r.tieneVistoBuenoProduccion) return 'Todavía falta el visto bueno de Jefe de Producción.';
    if (clave.isEmpty) return 'Ingresá tu clave.';
    return _ejecutar(() => _repo.recetaConfirmarGerente(r.id, clave));
  }

  Future<String?> rechazarReceta(RecetaPropuesta r, String motivo) async {
    if (!puedeAprobarReceta) return 'No tenés permiso para rechazar recetas.';
    if (motivo.trim().isEmpty) return 'Explicá el motivo del rechazo.';
    return _ejecutar(() => _repo.recetaRechazar(r.id, motivo.trim()));
  }

  // ---------------------------------------------------------------- pedir

  Future<String?> pedirFaltantes(List<VerificacionInsumo> faltantes) async {
    final aPedir = {for (final f in faltantes.where((f) => f.falta > 0)) f.itemId: f.falta};
    if (aPedir.isEmpty) return 'No hay faltantes para pedir.';
    return _ejecutar(() => _repo.pedirFaltantes(aPedir));
  }

  // ------------------------------------------------------------ preparado

  Future<String?> iniciarPreparado({
    required int? saborId,
    required double? cantidad,
    int? tanque,
  }) async {
    if (!puedeIniciar) return 'No tenés permiso para iniciar una producción de Jarabes.';
    if (saborId == null) return 'Elegí el sabor.';
    if (cantidad == null || cantidad.isNaN || cantidad <= 0) {
      return 'La cantidad de preparados debe ser mayor a cero.';
    }
    if (tanque != null && tanque <= 0) return 'Número de tanque inválido.';
    return _ejecutar(() async {
      await _repo.iniciarPreparado(saborId: saborId, cantidad: cantidad, tanque: tanque);
    });
  }

  Future<String?> finalizarPreparado(Preparado p, {required double? brix, String? observaciones}) async {
    if (!puedeFinalizar) return 'No tenés permiso para finalizar una producción de Jarabes.';
    if (p.estado != EstadoPreparado.enCurso) return 'Ese preparado ya se cerró.';
    if (brix == null || brix.isNaN || brix < 0 || brix > 100) {
      return 'Ingresá un Brix válido (0 a 100).';
    }
    if ((observaciones?.length ?? 0) > 300) return 'Las observaciones son demasiado largas.';
    return _ejecutar(() => _repo.finalizarPreparado(p.id, brix: brix, observaciones: observaciones));
  }

  Future<String?> anularPreparado(Preparado p, String motivo) async {
    if (!puedeFinalizar) return 'No tenés permiso para anular un preparado.';
    if (p.estado != EstadoPreparado.enCurso) return 'Solo se anula un preparado en curso.';
    final t = motivo.trim();
    if (t.length < 3) return 'Escribí el motivo (mínimo 3 caracteres).';
    return _ejecutar(() => _repo.anularPreparado(p.id, t));
  }

  Future<String?> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      await recargar();
      return null;
    } on ErrorNegocioJarabes catch (e) {
      await recargar();
      return e.mensaje;
    } catch (e) {
      if (kDebugMode) debugPrint('JarabesService: $e');
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

  List<Preparado> get historialFiltrado => filtro.aplicar(historial,
      texto: (x) => <String?>[x.sabor, 'lote ${x.nLote}', x.tanque?.toString(), x.responsableNombre, x.observaciones].whereType<String>().join(' '),
      fecha: (x) => x.fecha);

  ReporteTabla reporte() => ReporteTabla(
        titulo: 'Preparados de Jarabes',
        filtros: filtro.describir(),
        columnas: const ['Fecha', 'Sabor', 'Lote', 'Tanque', 'Estado', 'Preparados', 'Litros', 'Brix', 'Responsable'],
        filas: [
          for (final x in historialFiltrado) [x.fecha, x.sabor, x.nLote, x.tanque, x.estado.etiqueta, x.cantidadPreparados, x.litros, x.brix, x.responsableNombre]
        ],
      );
}
