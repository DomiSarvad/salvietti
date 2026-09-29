import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../services/movimiento_service.dart';
import '../../services/reporte_service.dart';
import '../../utils/formatters.dart';
import '../../utils/notificaciones.dart';
import '../../utils/texto.dart';
import '../../widgets/area_widgets.dart';
import '../../widgets/formulario_widgets.dart';
import '../../widgets/stock_status_badge.dart';
import 'importar_excel_dialog.dart';
import 'insumo_form_dialog.dart';
import 'movimiento_form_dialog.dart';

/// Lista de inventario de UNA de las cuatro áreas (cada una con su color e
/// ícono). Un único buscador filtra la tabla, y ese mismo filtro (más el
/// rango de fechas) es el que usan los reportes PDF/Excel de los botones
/// de arriba — o el botón de imprimir de cada fila, para un solo ítem.
class InventarioListScreen extends StatefulWidget {
  /// Área con la que abre (ej. al entrar desde una tarjeta del dashboard).
  final String? areaInicial;
  const InventarioListScreen({super.key, this.areaInicial});
  @override
  State<InventarioListScreen> createState() => _InventarioListScreenState();
}

class _InventarioListScreenState extends State<InventarioListScreen> {
  late AreaInventario _area;
  String _busqueda = '';
  DateTime? _desde;
  DateTime? _hasta;
  List<Insumo> _items = [];
  bool _cargando = true;
  bool _generando = false;
  Map<String, DateTime> _vencimientos = {};

  /// Jarabes solo trabaja con su propia área: ni ve ni puede elegir las
  /// demás.
  List<AreaInventario> _areasPara(Usuario usuario) =>
      usuario.esJarabes ? const [AreaInventario.jarabes] : AreaInventario.todas;

  @override
  void initState() {
    super.initState();
    final usuario = context.read<AuthService>().usuarioActual!;
    final disponibles = _areasPara(usuario);
    final inicial = widget.areaInicial != null
        ? AreaInventario.porId(widget.areaInicial!)
        : disponibles.first;
    _area = disponibles.contains(inicial) ? inicial : disponibles.first;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    var data = await InventarioService.listar(_area.tabla);
    if (_area.id == 'jarabes') {
      data = data.where((i) => i.area == 'jarabes').toList();
    } else if (_area.id == 'materia_prima') {
      data = data.where((i) => i.area != 'jarabes').toList();
    }
    final vencimientos = _area.tabla == 'materia_prima'
        ? await MovimientoService.proximosVencimientos()
        : <String, DateTime>{};
    if (!mounted) return;
    setState(() {
      _items = data;
      _vencimientos = vencimientos;
      _cargando = false;
    });
  }

  /// El buscador mira código, detalle, formato, color/tamaño, proveedor,
  /// unidad y el ESTADO del ítem (escribir "critico", "bajo" u "optimo"
  /// filtra por semáforo). Con varias palabras, deben coincidir todas.
  bool _coincide(Insumo i, String consulta) {
    final estado = SemaforoStock.etiqueta(SemaforoStock.evaluar(i.diasExistencia));
    final texto = sinTildes([
      i.codigo,
      i.detalle,
      i.formato,
      i.color,
      i.tamano,
      i.proveedorHabitual,
      i.unidadMedida,
      estado,
    ].whereType<String>().join(' '));
    return sinTildes(consulta)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .every(texto.contains);
  }

  List<Insumo> get _filtrados =>
      _items.where((i) => _busqueda.trim().isEmpty || _coincide(i, _busqueda)).toList();

  bool _puedeEditar(Usuario usuario) => usuario.puedeEditarArea(_area.id);

  Future<void> _elegirFecha({required bool esDesde}) async {
    final fecha = await showDatePicker(
      context: context,
      firstDate: esDesde ? DateTime(2024) : (_desde ?? DateTime(2024)),
      lastDate: esDesde ? (_hasta ?? DateTime.now()) : DateTime.now(),
      initialDate: (esDesde ? _desde : _hasta) ?? DateTime.now(),
    );
    if (fecha != null) setState(() => esDesde ? _desde = fecha : _hasta = fecha);
  }

  /// Reporte de movimientos del filtro actual (buscador + fechas), o de un
  /// solo ítem si se toca el botón de imprimir de su fila.
  Future<void> _generarReporte({required bool esPdf, Insumo? soloItem}) async {
    final responsable = context.read<AuthService>().usuarioActual!.nombreCompleto;
    final items = soloItem != null ? [soloItem] : _filtrados;
    if (items.isEmpty) {
      mostrarInfo(context, 'No hay ítems que coincidan con la búsqueda.');
      return;
    }
    setState(() => _generando = true);
    try {
      final ids = items.map((i) => i.id).toSet();
      var movimientos = await MovimientoService.listarPorFiltro(
        desde: _desde,
        // +1 día para incluir todo el día "hasta".
        hasta: _hasta?.add(const Duration(days: 1)),
        tabla: _area.tabla,
        itemId: soloItem?.id,
      );
      movimientos = movimientos.where((m) => ids.contains(m.itemId)).toList();
      if (!mounted) return;
      if (movimientos.isEmpty) {
        mostrarInfo(context, 'No hay movimientos en ese rango de fechas.');
        return;
      }
      final mapa = {for (final i in items) i.id: i};
      final titulo = soloItem != null
          ? 'Ficha de ${soloItem.detalle}'
          : 'Listado de movimientos · ${_area.etiqueta}';
      final subtitulo = soloItem != null
          ? 'Código ${soloItem.codigo} · ${_area.etiqueta}'
          : (_busqueda.trim().isEmpty
              ? 'Área ${_area.etiqueta}'
              : 'Área ${_area.etiqueta} · búsqueda: "${_busqueda.trim()}"');
      final ficha = soloItem != null ? _fichaDe(soloItem) : const <MapEntry<String, String>>[];
      // Nombre del archivo: qué lista es (o código + nombre del ítem) + fechas.
      final nombre = soloItem != null
          ? ReporteService.nombreIndividual(
              soloItem.codigo, soloItem.detalle, _desde, _hasta)
          : ReporteService.nombreListado(_area.etiqueta, _desde, _hasta);
      final bytes = esPdf
          ? await ReporteService.pdf(
              titulo: titulo,
              subtitulo: subtitulo,
              desde: _desde,
              hasta: _hasta,
              responsable: responsable,
              movimientos: movimientos,
              insumoPorId: mapa,
              ficha: ficha,
            )
          : ReporteService.excel(
              titulo: titulo,
              subtitulo: subtitulo,
              desde: _desde,
              hasta: _hasta,
              responsable: responsable,
              movimientos: movimientos,
              insumoPorId: mapa,
              ficha: ficha,
            );
      final mensaje =
          await ReporteService.guardar(bytes, esPdf: esPdf, nombre: nombre);
      if (mounted) mostrarExito(context, mensaje);
    } catch (e) {
      if (mounted) mostrarError(context, 'No se pudo generar el reporte: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  /// Datos del ítem para la ficha individual del PDF.
  List<MapEntry<String, String>> _fichaDe(Insumo i) => [
        MapEntry('Código', i.codigo),
        MapEntry('Detalle', i.detalle),
        MapEntry('Área', _area.etiqueta),
        if (i.formato != null && i.formato!.isNotEmpty) MapEntry('Formato', i.formato!),
        if ((i.color ?? i.tamano) != null) MapEntry('Color/Tamaño', (i.color ?? i.tamano)!),
        MapEntry('Stock real', '${fmtNum(i.cantidadReal, decimales: 0)} ${i.unidadMedida}'),
        MapEntry('Stock mínimo', '${fmtNum(i.stockMinimo, decimales: 0)} ${i.unidadMedida}'),
        if (i.proveedorHabitual != null && i.proveedorHabitual!.isNotEmpty)
          MapEntry('Proveedor habitual', i.proveedorHabitual!),
        MapEntry('Estado', SemaforoStock.etiqueta(SemaforoStock.evaluar(i.diasExistencia))),
      ];

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;
    final areas = _areasPara(usuario);

    // Un solo desplazamiento para toda la pantalla: el buscador, las fechas
    // y la tabla suben juntos (solo la barra superior y el menú quedan fijos).
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
          Row(
            children: [
              AreaIcono(_area, tamano: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Inventario · ${_area.etiqueta}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (areas.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in areas)
                  _ChipArea(
                    area: a,
                    seleccionada: a == _area,
                    onTap: () {
                      setState(() => _area = a);
                      _cargar();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 16),
          _barraAcciones(usuario),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: _area.color),
              hintText: 'Buscar por nombre o código...',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _area.color, width: 2)),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _CampoFecha(
                      etiqueta: 'Desde',
                      color: _area.color,
                      valor: _desde,
                      onTap: () => _elegirFecha(esDesde: true),
                      onLimpiar: () => setState(() => _desde = null))),
              const SizedBox(width: 12),
              Expanded(
                  child: _CampoFecha(
                      etiqueta: 'Hasta',
                      color: _area.color,
                      valor: _hasta,
                      onTap: () => _elegirFecha(esDesde: false),
                      onLimpiar: () => setState(() => _hasta = null))),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
                'Los reportes PDF/Excel incluyen lo que filtres aquí (sin filtros, el listado general) · '
                '${_filtrados.length} ítems',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          const SizedBox(height: 12),
          _cargando
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()))
              : _tabla(usuario),
        ],
    );
  }

  Widget _barraAcciones(Usuario usuario) {
    final registrar = _puedeEditar(usuario)
        ? _BotonGrande(
            icono: Icons.swap_vert,
            etiqueta: 'Registrar movimiento',
            color: _area.color,
            onTap: () => _abrirFormularioMovimiento(usuario.id),
          )
        : null;
    final nuevo = _puedeEditar(usuario)
        ? _BotonGrande(
            icono: Icons.add,
            etiqueta: 'Nuevo ítem',
            color: AppColors.primario,
            onTap: () => _abrirFormularioInsumo(usuario),
          )
        : null;
    final importar = _puedeEditar(usuario)
        ? _BotonGrande(
            icono: Icons.upload_file,
            etiqueta: 'Importar Excel',
            color: const Color(0xFF3DA35D),
            onTap: () => _importarExcel(usuario.id),
          )
        : null;
    final pdf = _BotonGrande(
      icono: Icons.picture_as_pdf,
      color: const Color(0xFFD32F2F),
      tooltip: 'Reporte PDF de los movimientos',
      cargando: _generando,
      onTap: _generando ? null : () => _generarReporte(esPdf: true),
    );
    final excel = _BotonGrande(
      icono: Icons.table_chart,
      color: const Color(0xFF1D6F42),
      tooltip: 'Reporte Excel de los movimientos',
      onTap: _generando ? null : () => _generarReporte(esPdf: false),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 820) {
        return Row(children: [
          if (registrar != null) Expanded(flex: 3, child: registrar),
          if (nuevo != null) ...[
            const SizedBox(width: 12),
            Expanded(flex: 2, child: nuevo),
          ],
          if (importar != null) ...[
            const SizedBox(width: 12),
            Expanded(flex: 2, child: importar),
          ],
          const SizedBox(width: 12),
          SizedBox(width: 84, child: pdf),
          const SizedBox(width: 12),
          SizedBox(width: 84, child: excel),
        ]);
      }
      return Column(children: [
        if (registrar != null) ...[
          SizedBox(width: double.infinity, child: registrar),
          const SizedBox(height: 10),
        ],
        if (nuevo != null) ...[
          SizedBox(width: double.infinity, child: nuevo),
          const SizedBox(height: 10),
        ],
        if (importar != null) ...[
          SizedBox(width: double.infinity, child: importar),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(child: pdf),
          const SizedBox(width: 12),
          Expanded(child: excel),
        ]),
      ]);
    });
  }

  Widget _tabla(Usuario usuario) {
    final esMP = _area.tabla == 'materia_prima';
    const estiloEncabezado =
        TextStyle(color: Colors.white, fontWeight: FontWeight.bold);

    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: c.maxWidth),
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(_area.color),
          headingTextStyle: estiloEncabezado,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columns: esMP
              ? const [
                  DataColumn(label: Text('Código')),
                  DataColumn(label: Text('Detalle')),
                  DataColumn(label: Text('Stock real')),
                  DataColumn(label: Text('Consumo/día')),
                  DataColumn(label: Text('Días est.')),
                  DataColumn(label: Text('Vencimiento aprox.')),
                  DataColumn(label: Text('Proveedor')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Opciones')),
                ]
              : const [
                  DataColumn(label: Text('Código')),
                  DataColumn(label: Text('Detalle')),
                  DataColumn(label: Text('Formato')),
                  DataColumn(label: Text('Color/Tamaño')),
                  DataColumn(label: Text('Stock real')),
                  DataColumn(label: Text('Cajas')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Opciones')),
                ],
          rows: _filtrados
              .map((i) => DataRow(
                  cells: esMP
                      ? [
                          DataCell(Text(i.codigo)),
                          DataCell(Text(i.detalle)),
                          DataCell(Text(
                              '${fmtNum(i.cantidadReal)} ${i.unidadMedida}')),
                          DataCell(Text(fmtNum(i.consumoPromedioDia))),
                          DataCell(Text(i.diasExistencia >= 999
                              ? '-'
                              : fmtNum(i.diasExistencia, decimales: 1))),
                          DataCell(Text(fmtFecha(_vencimientos[i.id]))),
                          DataCell(Text(i.proveedorHabitual ?? '-')),
                          DataCell(StockStatusBadge(
                              diasExistencia: i.diasExistencia)),
                          DataCell(_accionesFila(i, usuario)),
                        ]
                      : [
                          DataCell(Text(i.codigo)),
                          DataCell(Text(i.detalle)),
                          DataCell(Text(i.formato ?? '-')),
                          DataCell(Text(i.color ?? i.tamano ?? '-')),
                          DataCell(Text(
                              '${fmtNum(i.cantidadReal, decimales: 0)} ${i.unidadMedida}')),
                          DataCell(Text(
                              fmtNum(i.cantidadCajas ?? 0, decimales: 1))),
                          DataCell(StockStatusBadge(
                              diasExistencia: i.diasExistencia)),
                          DataCell(_accionesFila(i, usuario)),
                        ]))
              .toList(),
        ),
      ),
      ),
    );
  }

  Widget _accionesFila(Insumo i, Usuario usuario) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_puedeEditar(usuario))
          _BotonCuadrado(
            icono: Icons.edit_outlined,
            color: const Color(0xFFF0A030),
            tooltip: 'Editar',
            onTap: () => _abrirFormularioInsumo(usuario, insumo: i),
          ),
        if (_puedeEditar(usuario))
          _BotonCuadrado(
            icono: Icons.delete_outline,
            color: const Color(0xFFD9534F),
            tooltip: 'Eliminar',
            onTap: () => _confirmarEliminar(i, usuario.id),
          ),
        _BotonCuadrado(
          icono: Icons.print_outlined,
          color: const Color(0xFF5CB85C),
          tooltip: 'Imprimir movimientos de este ítem (PDF)',
          onTap: _generando ? null : () => _generarReporte(esPdf: true, soloItem: i),
        ),
      ],
    );
  }

  Future<void> _abrirFormularioInsumo(Usuario usuario, {Insumo? insumo}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => InsumoFormDialog(
          tabla: _area.tabla,
          insumo: insumo,
          usuarioId: usuario.id,
          esJarabes: usuario.esJarabes || _area.id == 'jarabes'),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _importarExcel(String usuarioId) async {
    final importado = await showDialog<bool>(
      context: context,
      builder: (_) => ImportarExcelDialog(
          area: _area, existentes: _items, usuarioId: usuarioId),
    );
    if (importado == true) _cargar();
  }

  Future<void> _abrirFormularioMovimiento(String usuarioId) async {
    final registrado = await showDialog<bool>(
      context: context,
      builder: (_) => MovimientoFormDialog(
          items: _items, tabla: _area.tabla, usuarioId: usuarioId),
    );
    if (registrado == true) _cargar();
  }

  Future<void> _confirmarEliminar(Insumo i, String usuarioId) async {
    final motivoCtrl = TextEditingController();
    final ok = await confirmarAccion(
      context,
      titulo: '¿Eliminar ítem?',
      mensaje: '"${i.detalle}" no se borrará físicamente: quedará marcado como '
          'inactivo y registrado en la bitácora de eliminaciones.',
      extra: TextField(
        controller: motivoCtrl,
        decoration: decoracionFormulario(hint: 'Motivo (opcional)'),
      ),
    );
    if (ok) {
      await InventarioService.eliminar(i.tabla, i.id, usuarioId, motivoCtrl.text);
      if (mounted) mostrarExito(context, 'Ítem eliminado correctamente.');
      _cargar();
    }
  }
}

/// Pestaña de área: relleno del color del área cuando está elegida.
class _ChipArea extends StatelessWidget {
  final AreaInventario area;
  final bool seleccionada;
  final VoidCallback onTap;
  const _ChipArea(
      {required this.area, required this.seleccionada, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: seleccionada ? area.color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: area.color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(area.icono,
                size: 18, color: seleccionada ? Colors.white : area.color),
            const SizedBox(width: 6),
            Text(area.etiqueta,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: seleccionada ? Colors.white : area.color)),
          ],
        ),
      ),
    );
  }
}

/// Botón ancho de la barra superior (estilo "Registrar Reclamo").
class _BotonGrande extends StatelessWidget {
  final IconData icono;
  final String? etiqueta;
  final Color color;
  final String? tooltip;
  final bool cargando;
  final VoidCallback? onTap;
  const _BotonGrande({
    required this.icono,
    required this.color,
    this.etiqueta,
    this.tooltip,
    this.cargando = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final boton = Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              cargando
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color))
                  : Icon(icono, color: color, size: 26),
              if (etiqueta != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(etiqueta!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: boton) : boton;
  }
}

/// Campo de fecha con la etiqueta "Desde"/"Hasta" flotando sobre el borde.
class _CampoFecha extends StatelessWidget {
  final String etiqueta;
  final Color color;
  final DateTime? valor;
  final VoidCallback onTap;
  final VoidCallback onLimpiar;
  const _CampoFecha({
    required this.etiqueta,
    required this.color,
    required this.valor,
    required this.onTap,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          suffixIcon: valor == null
              ? const Icon(Icons.calendar_today, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onLimpiar,
                ),
        ),
        child: Text(
          valor == null ? 'dd/mm/aaaa' : fmtFecha(valor),
          style: TextStyle(color: valor == null ? Colors.black38 : Colors.black87),
        ),
      ),
    );
  }
}

/// Botón cuadrado de color para la columna de opciones de cada fila.
class _BotonCuadrado extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  const _BotonCuadrado(
      {required this.icono,
      required this.color,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: onTap == null ? Colors.grey.shade300 : color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icono, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
