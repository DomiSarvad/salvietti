import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import '../../../shared/opciones_deslizables.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/categoria_inv.dart';
import '../models/existencia_item.dart';
import '../repositories/inventario_repository.dart';
import '../../../shared/filtros/barra_filtros.dart';
import '../services/inventario_service.dart';
import 'balance_screen.dart';
import '../widgets/conteo_dialog.dart';
import '../widgets/item_form_dialog.dart';
import '../widgets/salida_directa_dialog.dart';
import '../widgets/movimientos_dialog.dart';


/// Inventario por almacenes (General, Jarabes, Soplado), ordenado como se
/// busca en un almacén real: se entra por TIPO de artículo (Tapas,
/// Etiquetas, Preformas…), se baja por sus divisiones (PET / Vidrio…) y en
/// cada nivel se ve la lista de ítems con su stock, conteo, días de
/// existencia y movimientos. Solo UI: todo lo demás lo resuelve el service.
class AlmacenesScreen extends StatelessWidget {
  /// Con qué almacén abre (ej. al entrar desde una tarjeta del Inicio).
  /// Null = el primero que el rol pueda ver.
  final String? almacenInicial;
  const AlmacenesScreen({super.key, this.almacenInicial});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => InventarioService(SupabaseInventarioRepository(), usuario)
        ..iniciar(almacenPreferido: almacenInicial),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<InventarioService>().recargar(),
        child: const _Vista(),
      ),
    );
  }
}

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoAlmacenChips = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Almacenes',
    texto: 'Elegí con qué almacén trabajar.',
  );
  final _pasoBuscador = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Buscador',
    texto: 'Busca en todo el almacén.',
  );
  final _pasoCategorias = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Categorías',
    texto: 'Muestra los ítems de la categoría y sus subdivisiones.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'almacenes', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoAlmacenChips, _pasoBuscador, _pasoCategorias];

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<InventarioService>();

    if (svc.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (svc.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(svc.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (svc.almacenes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a ningún almacén.'),
        ),
      );
    }

    final items = svc.mostrarTabla ? svc.visibles : const <ExistenciaItem>[];

    // La sección de categorías vive DENTRO de `_Cabecera` (no acá como ítem
    // aparte del ListView): antes, al ser un ítem más abajo que el propio
    // `_Cabecera` (ya de por sí alto, con chips de almacén y buscador), un
    // `ListView` angosto o con poco alto podía no montarla todavía cuando el
    // tour arrancaba solo al entrar, y ese paso se salteaba en silencio —
    // el mismo problema que ya se documentó para historiales sin límite,
    // aplicado acá por error aunque Almacenes no tiene una lista así.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Cabecera(
          svc: svc,
          pasoAlmacenChips: _pasoAlmacenChips,
          pasoBuscador: _pasoBuscador,
          pasoCategorias: _pasoCategorias,
          pasosAyuda: _pasosAyuda,
        ),
        if (svc.buscandoEnTodoElAlmacen) ...[
          const SizedBox(height: 10),
          _AvisoBusquedaGlobal(svc: svc),
        ],
        const SizedBox(height: 16),
        if (!svc.mostrarTabla)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Elegí una categoría para ver sus ítems, buscá por nombre o código, o '
              'elegí fechas para ver qué se movió. El PDF y el Excel, sin filtros, '
              'salen con todo el almacén.',
              style: TextStyle(color: Colors.black54),
            ),
          )
        else if (items.isEmpty)
          _SinItems(svc: svc)
        else ...[
          // De a tandas: una tabla de cientos de filas se arma entera de
          // nuevo con cada cambio. El PDF ("Imprimir reporte") sale completo.
          _TablaItems(
              svc: svc,
              items: items.length > svc.limiteTabla ? items.sublist(0, svc.limiteTabla) : items),
          if (items.length > svc.limiteTabla)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: svc.mostrarMasFilas,
                  icon: const Icon(Icons.expand_more),
                  label: Text('Mostrar más (viendo ${svc.limiteTabla} de ${items.length})'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Avisa cuando hay una búsqueda activa mientras se está dentro de una
/// categoría: los resultados son de TODO el almacén, no solo de acá adentro
/// (si no, parecería que la búsqueda "no encuentra" algo que sí existe, solo
/// que está en otra sección).
class _AvisoBusquedaGlobal extends StatelessWidget {
  final InventarioService svc;
  const _AvisoBusquedaGlobal({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primario.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.travel_explore, size: 16, color: AppColors.primario),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Buscando en todo "${svc.almacenes.firstWhere((a) => a.id == svc.almacenId).nombre}", '
            'no solo en ${svc.textoRuta(svc.categoriaFiltro!)}.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.primario, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final InventarioService svc;
  final PasoAyuda pasoAlmacenChips;
  final PasoAyuda pasoBuscador;
  final PasoAyuda pasoCategorias;
  final List<PasoAyuda> Function() pasosAyuda;
  const _Cabecera({
    required this.svc,
    required this.pasoAlmacenChips,
    required this.pasoBuscador,
    required this.pasoCategorias,
    required this.pasosAyuda,
  });

  Future<void> _nuevo(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => ItemFormDialog(servicio: svc, categoriaInicial: svc.categoriaFiltro),
    );
  }

  Future<void> _balance(BuildContext context) async {
    final almacen = svc.almacenes.firstWhere((a) => a.id == svc.almacenId);
    final guardado = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BalanceScreen(almacenId: almacen.id, almacenNombre: almacen.nombre),
    ));
    if (guardado == true) await svc.recargar();
  }

  Future<void> _salidaDirecta(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SalidaDirectaDialog(servicio: svc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actual = svc.categoriaFiltro;
    final ruta = actual == null ? const <CategoriaInv>[] : svc.rutaDe(actual);
    final hijos = svc.hijosDe(actual);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Almacenes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'almacenes', pasos: pasosAyuda),
          ],
        ),
        const SizedBox(height: 10),
        // Wrap, no Row: con los tres botones juntos (Balance, Salida directa,
        // Nuevo ítem) un Row fijo se desborda en una pantalla angosta — el
        // título "Almacenes" de arriba quedaba con un ancho negativo y el
        // texto se partía letra por letra. Acá simplemente pasan a la
        // siguiente línea.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (svc.puedeEditar)
              OutlinedButton.icon(
                onPressed: () => _balance(context),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Balance'),
              ),
            if (svc.puedeSalidaDirecta)
              OutlinedButton.icon(
                onPressed: () => _salidaDirecta(context),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Salida directa'),
              ),
            if (svc.puedeCrear)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _nuevo(context),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo ítem'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Una sola fila que se desliza de costado, como las áreas de Informes.
        pasoAlmacenChips.envolver(
          OpcionesDeslizables<String?>(
            opciones: [for (final a in svc.almacenes) a.id],
            seleccionada: svc.almacenId,
            etiqueta: (id) => svc.almacenes.firstWhere((a) => a.id == id).nombre,
            icono: (id) => iconoAlmacen(svc.almacenes.firstWhere((a) => a.id == id).nombre),
            onElegir: (id) => svc.seleccionarAlmacen(id!),
          ),
        ),
        const SizedBox(height: 10),
        // Buscador común: texto, Desde/Hasta y PDF/Excel de lo que se ve. Con
        // fechas, la tabla muestra lo que se movió en ese período (entradas y
        // salidas). En la raíz sin filtros, el reporte sale con todo el almacén.
        pasoBuscador.envolver(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BarraFiltros(
              filtro: svc.filtro,
              onCambio: svc.filtrar,
              reporte: svc.reporte,
              // Con coma, varios productos a la vez: "tapa negra, preforma 28".
              hint: 'Buscar (varios: separá con coma)',
            ),
            const SizedBox(height: 8),
            _FiltrosExtra(svc: svc),
            if (svc.cargandoPeriodo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (svc.errorPeriodo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(svc.errorPeriodo!, style: const TextStyle(color: Color(0xFFDC2626))),
              ),
          ],
        )),
        const SizedBox(height: 8),
        // Migas de pan: dónde estoy y cómo volver.
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              avatar: const Icon(Icons.home_outlined, size: 16),
              label: const Text('Inicio'),
              onPressed: () => svc.filtrarCategoria(null),
            ),
            for (final c in ruta) ...[
              const Icon(Icons.chevron_right, size: 16, color: Colors.black38),
              ActionChip(label: Text(c.nombre), onPressed: () => svc.filtrarCategoria(c.id)),
            ],
          ],
        ),
        if (hijos.isNotEmpty) ...[
          const SizedBox(height: 14),
          pasoCategorias.envolver(
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final c in hijos) _TarjetaCategoria(svc: svc, cat: c)],
            ),
          ),
          if (actual != null && svc.busqueda.trim().isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'La lista de abajo ya incluye TODOS los ítems de esta sección y sus '
              'divisiones — no hace falta entrar a cada una. Tocá una tarjeta solo '
              'para acotar la vista a esa división.',
              style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ],
    );
  }
}

/// Una categoría para entrar a ella: cuántos ítems tiene y cuáles piden atención.
class _TarjetaCategoria extends StatelessWidget {
  final InventarioService svc;
  final CategoriaInv cat;
  const _TarjetaCategoria({required this.svc, required this.cat});

  static IconData _icono(String nombre) {
    final n = nombre.toLowerCase();
    if (n.contains('tapa')) return Icons.adjust;
    if (n.contains('etiqueta') || n.contains('sticker') || n.contains('papel')) {
      return Icons.label_outline;
    }
    if (n.contains('preforma')) return Icons.local_drink_outlined;
    if (n.contains('termo')) return Icons.compress;
    if (n.contains('envase')) return Icons.liquor;
    if (n.contains('caja')) return Icons.inventory_2_outlined;
    if (n.contains('limpieza') || n.contains('saneamiento')) {
      return Icons.cleaning_services_outlined;
    }
    if (n.contains('seguridad')) return Icons.health_and_safety_outlined;
    if (n.contains('mantenimiento') || n.contains('plomer') || n.contains('electric') ||
        n.contains('mecánico') || n.contains('civil')) {
      return Icons.build_outlined;
    }
    if (n.contains('escritorio')) return Icons.edit_note;
    if (n.contains('laboratorio')) return Icons.science_outlined;
    if (n.contains('codific')) return Icons.qr_code_2;
    if (n == 'pet') return Icons.local_drink_outlined;
    if (n == 'vidrio') return Icons.wine_bar_outlined;
    return Icons.folder_open_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final r = svc.resumenDe(cat.id);
    final sub = svc.hijosDe(cat.id).length;

    Widget pill(String texto, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(texto,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        );

    return SizedBox(
      width: 230,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => svc.filtrarCategoria(cat.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(_icono(cat.nombre), color: AppColors.primario),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cat.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ]),
                const SizedBox(height: 6),
                Text(
                  '${r.items} ítem${r.items == 1 ? '' : 's'}'
                  '${sub > 0 ? ' · $sub división${sub == 1 ? '' : 'es'}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (r.pedidos > 0 || r.criticos > 0) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (r.criticos > 0)
                      pill('${r.criticos} crítico${r.criticos == 1 ? '' : 's'}',
                          const Color(0xFFDC2626)),
                    if (r.pedidos > 0) pill('${r.pedidos} a pedir', const Color(0xFFD97706)),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SinItems extends StatelessWidget {
  final InventarioService svc;
  const _SinItems({required this.svc});

  @override
  Widget build(BuildContext context) {
    final hayFiltro = svc.busqueda.trim().isNotEmpty || svc.soloPedido;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E7EB)),
      ),
      child: Column(children: [
        const Icon(Icons.inbox_outlined, size: 36, color: Colors.black38),
        const SizedBox(height: 8),
        Text(
          hayFiltro
              ? 'Ningún ítem coincide con la búsqueda o el filtro.'
              : 'Todavía no hay ítems en esta categoría.',
          style: const TextStyle(color: Colors.black54),
        ),
        if (!hayFiltro && svc.puedeCrear) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) =>
                  ItemFormDialog(servicio: svc, categoriaInicial: svc.categoriaFiltro),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Agregar el primero'),
          ),
        ],
      ]),
    );
  }
}

/// Lista de ítems en tabla (como el inventario anterior): stock del sistema,
/// último conteo físico, mínimo, días de existencia y estado. Cada fila tiene
/// sus movimientos, conteo, edición y baja según el permiso del rol.
class _TablaItems extends StatelessWidget {
  final InventarioService svc;
  final List<ExistenciaItem> items;
  const _TablaItems({required this.svc, required this.items});

  Future<void> _movimientos(BuildContext context, ExistenciaItem item) => showDialog<void>(
        context: context,
        builder: (_) => MovimientosDialog(servicio: svc, item: item),
      );

  Future<void> _contar(BuildContext context, ExistenciaItem item) => showDialog<bool>(
        context: context,
        builder: (_) => ConteoDialog(servicio: svc, item: item),
      );

  Future<void> _editar(BuildContext context, ExistenciaItem item) async {
    try {
      final completo = await svc.cargarItem(item.itemId);
      if (!context.mounted) return;
      await showDialog<bool>(
        context: context,
        builder: (_) => ItemFormDialog(servicio: svc, item: completo),
      );
    } catch (_) {
      if (context.mounted) mostrarError(context, 'No se pudo abrir el ítem.');
    }
  }

  Future<void> _eliminar(BuildContext context, ExistenciaItem item) async {
    final ok = await confirmar(
      context,
      titulo: '¿Eliminar ítem?',
      texto: '"${item.detalle}" deja de mostrarse en el inventario.',
      textoSi: 'Sí, eliminar',
      peligro: true,
    );
    if (!ok || !context.mounted) return;
    final error = await svc.desactivarItem(item.itemId);
    if (!context.mounted) return;
    error == null ? avisoExito(context, 'Eliminado', 'El ítem se quitó del inventario.') : mostrarError(context, error);
  }

  Color _colorSituacion(SituacionStock s) {
    switch (s) {
      case SituacionStock.critico:
        return SemaforoStock.color(EstadoStock.critico);
      case SituacionStock.bajo:
        return SemaforoStock.color(EstadoStock.bajo);
      case SituacionStock.optimo:
        return SemaforoStock.color(EstadoStock.optimo);
      case SituacionStock.sinDatos:
        return Colors.black45;
    }
  }

  Widget _pill(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columnSpacing: 22,
          columns: [
            const DataColumn(label: Text('Código')),
            const DataColumn(label: Text('Detalle')),
            const DataColumn(label: Text('Ubicación')),
            const DataColumn(label: Text('Stock'), numeric: true),
            const DataColumn(label: Text('Últ. conteo'), numeric: true),
            const DataColumn(label: Text('Mínimo'), numeric: true),
            const DataColumn(label: Text('Días'), numeric: true),
            const DataColumn(label: Text('Estado')),
            if (svc.periodoActivo) ...const [
              DataColumn(label: Text('Entradas'), numeric: true),
              DataColumn(label: Text('Salidas'), numeric: true),
            ],
            const DataColumn(label: Text('Acciones')),
          ],
          rows: [for (final e in items) _fila(context, e)],
        ),
      ),
    );
  }

  DataRow _fila(BuildContext context, ExistenciaItem e) {
    final sit = svc.situacion(e);
    final dif = e.diferencia;

    return DataRow(cells: [
      DataCell(Text(e.codigo, style: const TextStyle(color: Colors.black54))),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(e.detalle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      )),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(svc.textoRutaRelativa(e.categoriaId),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      )),
      DataCell(Text('${fmtNum(e.cantidadSistema)} ${e.unidad}',
          style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(e.cantidadReal == null
          ? const Text('—', style: TextStyle(color: Colors.black38))
          : Text(
              '${fmtNum(e.cantidadReal)}'
              '${dif == null || dif == 0 ? '' : ' (${dif > 0 ? '+' : ''}${fmtNum(dif)})'}',
              style: TextStyle(
                  color: dif == null || dif == 0 ? AppColors.primario : const Color(0xFFD97706),
                  fontWeight: FontWeight.w600))),
      DataCell(Text(e.stockMinimo == null ? '—' : fmtNum(e.stockMinimo))),
      DataCell(Text(e.diasExistencia == null ? '—' : fmtNum(e.diasExistencia, decimales: 1))),
      DataCell(Wrap(spacing: 6, children: [
        _pill(InventarioService.textoSituacion(sit), _colorSituacion(sit)),
        if (svc.necesitaPedido(e)) _pill('Pedido', const Color(0xFFDC2626)),
      ])),
      if (svc.periodoActivo) ...[
        DataCell(Text(fmtNum(svc.movimientoDe(e)!.entradas),
            style: const TextStyle(color: Color(0xFF16A34A)))),
        DataCell(Text(fmtNum(svc.movimientoDe(e)!.salidas),
            style: const TextStyle(color: Color(0xFFDC2626)))),
      ],
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Movimientos',
          icon: const Icon(Icons.swap_vert),
          onPressed: () => _movimientos(context, e),
        ),
        if (svc.puedeEditar)
          IconButton(
            tooltip: 'Contar (físico)',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => _contar(context, e),
          ),
        if (svc.puedeEditar)
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editar(context, e),
          ),
        if (svc.puedeEliminar)
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
            onPressed: () => _eliminar(context, e),
          ),
      ])),
    ]);
  }
}

/// Debajo del buscador, en una fila que se desliza: "Tipo" (elegir varios
/// tipos de una vez), los tipos elegidos (con x para quitarlos) y "Pedido".
class _FiltrosExtra extends StatelessWidget {
  final InventarioService svc;
  const _FiltrosExtra({required this.svc});

  Future<void> _elegir(BuildContext context) async {
    final elegidos = {...svc.tiposFiltro};
    final r = await showModalBottomSheet<Set<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Filtrar por tipo',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final t in svc.tipos)
                    CheckboxListTile(
                      value: elegidos.contains(t.id),
                      title: Text(t.nombre),
                      activeColor: AppColors.primario,
                      onChanged: (v) => setLocal(() => v == true ? elegidos.add(t.id) : elegidos.remove(t.id)),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, <int>{}),
                    child: const Text('Quitar todos'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: () => Navigator.pop(ctx, elegidos),
                    child: const Text('Aplicar'),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (r != null) svc.filtrarTipos(r);
  }

  @override
  Widget build(BuildContext context) {
    final elegidos = [for (final t in svc.tipos) if (svc.tiposFiltro.contains(t.id)) t];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ActionChip(
          avatar: const Icon(Icons.filter_list, size: 16),
          label: Text(elegidos.isEmpty ? 'Tipo' : 'Tipo (${elegidos.length})'),
          onPressed: svc.tipos.isEmpty ? null : () => _elegir(context),
        ),
        for (final t in elegidos)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InputChip(
              label: Text(t.nombre),
              selected: true,
              selectedColor: AppColors.primario.withValues(alpha: 0.15),
              showCheckmark: false,
              onDeleted: () => svc.filtrarTipos({...svc.tiposFiltro}..remove(t.id)),
            ),
          ),
        if (svc.muestraFiltroPedido)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: const Text('Pedido'),
              avatar: const Icon(Icons.shopping_cart_outlined, size: 16),
              selected: svc.soloPedido,
              onSelected: (_) => svc.alternarSoloPedido(),
            ),
          ),
      ]),
    );
  }
}
