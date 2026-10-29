import 'package:flutter/foundation.dart';
import '../../../shared/busqueda_local.dart';
import '../../../core/modulos.dart';
import '../../../models/usuario.dart';
import '../models/solicitud.dart';
import '../../jarabes/models/jarabes_modelos.dart' show RecetaPropuesta;
import '../repositories/solicitudes_repository.dart';
import '../../../shared/filtros/filtro_lista.dart';
import '../../../shared/reportes/reporte_tabla.dart';

enum BandejaSolicitudes {
  mias('Mis solicitudes'),
  porAprobar('Por aprobar'),
  resueltas('Resueltas'),
  recetas('Recetas');

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

  /// Propuestas de receta de los últimos [diasRecetas] días (pendientes y
  /// resueltas): se aprueban en Jarabes, pero su historial se ve acá.
  List<RecetaPropuesta> recetas = [];
  static const diasRecetas = 90;
  BandejaSolicitudes bandeja = BandejaSolicitudes.mias;
  bool cargando = true;
  String? error;

  bool _puede(String modulo, String accion) =>
      _usuario.puede(modulo, accion, reglaAnterior: false);

  bool get puedeVer => _puede(Modulo.solicitudes, Accion.ver);
  bool get puedeCrear => _puede(Modulo.solicitudes, Accion.crear);
  bool get puedeAprobar => _puede(Modulo.aprobaciones, Accion.aprobar);
  bool get puedeVerRecetas => _puede(Modulo.recetas, Accion.ver);

  /// Las pestañas que tienen sentido para este rol: quien pide ve las suyas;
  /// quien aprueba (el Gerente) ve lo que espera respuesta y lo resuelto. Al
  /// Gerente antes le aparecía "Mis solicitudes" aunque él no pide nada.
  List<BandejaSolicitudes> get bandejas => [
        if (puedeCrear || !puedeAprobar) BandejaSolicitudes.mias,
        if (puedeAprobar) ...[BandejaSolicitudes.porAprobar, BandejaSolicitudes.resueltas],
        if (puedeVerRecetas) BandejaSolicitudes.recetas,
      ];

  /// La constancia es el comprobante de lo que resolvió Gerencia (aprobada o
  /// rechazada, con su motivo): mientras está pendiente no hay nada que
  /// constar. Imprimirla es opcional.
  bool puedeImprimir(Solicitud s) => s.estado != EstadoSolicitud.pendiente;

  /// El mensaje es "mío" (va a la derecha en la conversación) si lo escribió
  /// quien está mirando: el pedido si lo hizo él; la respuesta si es quien aprueba.
  bool esMia(Solicitud s) => s.solicitanteId == _usuario.id;

  Future<void> iniciar() async {
    cargando = true;
    error = null;
    bandeja = puedeAprobar ? BandejaSolicitudes.porAprobar : BandejaSolicitudes.mias;
    if (!bandejas.contains(bandeja) && bandejas.isNotEmpty) bandeja = bandejas.first;
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
      final r = await Future.wait<Object>([
        _repo.solicitudes(),
        puedeVerRecetas
            ? _repo.recetas(DateTime.now().subtract(const Duration(days: diasRecetas)))
                // Sin la tabla de Jarabes (o sin permiso) las solicitudes se ven igual.
                .catchError((_) => <RecetaPropuesta>[])
            : Future.value(<RecetaPropuesta>[]),
      ]);
      solicitudes = r[0] as List<Solicitud>;
      recetas = r[1] as List<RecetaPropuesta>;
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
    if (!bandejas.contains(b)) return;
    bandeja = b;
    notifyListeners();
  }

  /// Una solicitud recién cargada de nuevo (después de resolverla, para que
  /// la conversación abierta muestre la respuesta).
  Solicitud? porId(int id) {
    for (final s in solicitudes) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Solicitud> get visibles {
    switch (bandeja) {
      case BandejaSolicitudes.mias:
        return solicitudes.where((s) => s.solicitanteId == _usuario.id).toList();
      case BandejaSolicitudes.porAprobar:
        return solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).toList();
      case BandejaSolicitudes.resueltas:
        return solicitudes.where((s) => s.estado != EstadoSolicitud.pendiente).toList();
      case BandejaSolicitudes.recetas:
        return const []; // esta pestaña muestra [recetasFiltradas]
    }
  }

  int get pendientesDeAprobar =>
      solicitudes.where((s) => s.estado == EstadoSolicitud.pendiente).length;

  // Se busca en memoria (CatalogoLocal): una consulta, no una por letra.
  late final _catItems =
      CatalogoLocal<ItemReferencia>(_repo.items, (i) => '${i.codigo} ${i.detalle}');
  Future<List<ItemReferencia>> buscarItems(String texto) => _catItems.buscar(texto);

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

  // ------------------------------------------------- buscador y reporte

  /// Filtro del buscador (texto + Desde/Hasta): define qué se ve en la lista y
  /// qué sale en el reporte PDF/Excel ("lo que ves es lo que se imprime").
  FiltroLista filtro = const FiltroLista();

  void filtrar(FiltroLista f) {
    filtro = f;
    notifyListeners();
  }

  List<RecetaPropuesta> get recetasFiltradas => filtro.aplicar(recetas,
      texto: (r) => <String?>[r.sabor, r.creadaPorNombre, r.estado.etiqueta, r.resueltaPorNombre, r.motivoRechazo, r.aprobadaCalidadNombre, r.aprobadaProduccionNombre].whereType<String>().join(' '),
      fecha: (r) => r.creadaEn);

  List<Solicitud> get visiblesFiltrados => filtro.aplicar(visibles,
      texto: (x) => <String?>[TipoSolicitud.etiqueta(x.tipo), x.asunto, x.detalle, x.itemDetalle, x.solicitanteNombre, x.respuesta, x.estado.etiqueta].whereType<String>().join(' '),
      fecha: (x) => x.fecha);

  ReporteTabla reporte() => bandeja == BandejaSolicitudes.recetas
      ? ReporteTabla(
          titulo: 'Propuestas de receta',
          filtros: filtro.describir(),
          columnas: const ['Fecha', 'Sabor', 'Propuesta por', 'Estado', 'Resuelta por', 'Motivo'],
          filas: [
            for (final r in recetasFiltradas)
              [r.creadaEn, r.sabor, r.creadaPorNombre, r.estado.etiqueta, r.resueltaPorNombre, r.motivoRechazo]
          ],
        )
      : ReporteTabla(
        titulo: 'Solicitudes a Gerencia',
        filtros: filtro.describir(),
        columnas: const ['Fecha', 'Tipo', 'Asunto', 'Ítem', 'Cantidad', 'Solicitante', 'Estado', 'Respuesta'],
        filas: [
          for (final x in visiblesFiltrados) [x.fecha, TipoSolicitud.etiqueta(x.tipo), x.asunto, x.itemDetalle, x.cantidadSugerida, x.solicitanteNombre, x.estado.etiqueta, x.respuesta]
        ],
      );
}
