import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../services/archivo_service.dart';
import '../../services/importacion_service.dart';
import '../../utils/formatters.dart';
import '../../utils/notificaciones.dart';
import '../../widgets/formulario_widgets.dart';

const _mimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Importar desde Excel, con dos formatos:
///  * Ítems: da de alta el catálogo (los que ya existen se omiten).
///  * Movimientos: carga el historial (entradas/salidas/ajustes) sobre los
///    ítems existentes, creando los que falten una sola vez, sin repetir lo
///    que ya se importó, y eligiendo si afecta o no al stock.
/// Devuelve true si se creó algo.
class ImportarExcelDialog extends StatefulWidget {
  final AreaInventario area;
  final List<Insumo> existentes;
  final String usuarioId;
  const ImportarExcelDialog({
    super.key,
    required this.area,
    required this.existentes,
    required this.usuarioId,
  });

  @override
  State<ImportarExcelDialog> createState() => _ImportarExcelDialogState();
}

class _ImportarExcelDialogState extends State<ImportarExcelDialog> {
  String _modo = 'items'; // 'items' | 'movimientos'
  ResultadoLectura? _lecturaItems;
  ResultadoLecturaMov? _lecturaMov;
  Uint8List? _bytes;
  String? _nombreArchivo;
  bool _crearItems = true;
  bool _soloHistorial = true;

  String? _error;
  bool _leyendo = false;
  bool _importando = false;
  int _hechos = 0;
  int _total = 0;

  bool get _esItems => _modo == 'items';
  bool get _hayLectura => _esItems ? _lecturaItems != null : _lecturaMov != null;

  void _cambiarModo(String modo) {
    setState(() {
      _modo = modo;
      _lecturaItems = null;
      _lecturaMov = null;
      _bytes = null;
      _error = null;
    });
  }

  Future<void> _elegirArchivo() async {
    setState(() {
      _error = null;
      _leyendo = true;
    });
    try {
      final r = await FilePicker.pickFiles(
        dialogTitle: 'Elegí el Excel',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final archivo = r.files.first;
      if (archivo.bytes == null) {
        setState(() => _error = 'No se pudo leer el archivo elegido.');
        return;
      }
      _bytes = archivo.bytes;
      _nombreArchivo = archivo.name;
      await _procesar();
    } catch (e) {
      setState(() => _error = 'No se pudo abrir el selector de archivos: $e');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  /// Interpreta el archivo ya elegido (se vuelve a llamar si cambia una opción).
  Future<void> _procesar() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _leyendo = true;
      _error = null;
    });
    try {
      if (_esItems) {
        final l = ImportacionService.leer(bytes, widget.area, widget.existentes);
        setState(() {
          _lecturaItems = l.errorGeneral == null ? l : null;
          _error = l.errorGeneral;
        });
      } else {
        final l = ImportacionMovService.leer(bytes, widget.area, widget.existentes,
            crearItems: _crearItems);
        if (l.errorGeneral != null) {
          setState(() {
            _lecturaMov = null;
            _error = l.errorGeneral;
          });
        } else {
          // Marca lo que ya se importó antes para no duplicarlo (necesita red).
          try {
            await ImportacionMovService.marcarYaImportados(l.filas);
          } catch (_) {
            setState(() {
              _lecturaMov = null;
              _error = 'Se necesita conexión para revisar qué movimientos ya '
                  'se importaron y evitar duplicados.';
            });
            return;
          }
          setState(() => _lecturaMov = l);
        }
      }
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _descargarPlantilla() async {
    try {
      final bytes = _esItems
          ? ImportacionService.plantilla(widget.area)
          : ImportacionMovService.plantilla(widget.area);
      final mensaje = await ArchivoService.guardar(
        bytes,
        nombre:
            'Plantilla ${_esItems ? 'inventario' : 'movimientos'} ${widget.area.etiqueta}',
        ext: 'xlsx',
        mimeType: _mimeXlsx,
      );
      if (mounted) mostrarExito(context, mensaje);
    } catch (e) {
      if (mounted) mostrarError(context, 'No se pudo guardar la plantilla: $e');
    }
  }

  Future<void> _importar() async {
    setState(() {
      _importando = true;
      _hechos = 0;
      _error = null;
    });
    if (_esItems) {
      final nuevos = _lecturaItems!.nuevas.map((f) => f.insumo!).toList();
      _total = nuevos.length;
      final r = await ImportacionService.importar(
        nuevos,
        widget.usuarioId,
        widget.area,
        onProgreso: (h, _) {
          if (mounted) setState(() => _hechos = h);
        },
      );
      if (!mounted) return;
      if (r.creados > 0) {
        mostrarExito(
            context,
            r.fallidos == 0
                ? 'Se importaron ${r.creados} ítems.'
                : 'Se importaron ${r.creados} ítems; ${r.fallidos} no se pudieron crear.');
        Navigator.pop(context, true);
      } else {
        setState(() {
          _importando = false;
          _error = 'No se pudo importar${r.primerError != null ? ': ${r.primerError}' : '.'}';
        });
      }
    } else {
      final l = _lecturaMov!;
      _total = l.itemsPorCrear.length + l.importables.length;
      final r = await ImportacionMovService.importar(
        l,
        widget.usuarioId,
        widget.area,
        soloHistorial: _soloHistorial,
        onProgreso: (h, t) {
          if (mounted) {
            setState(() {
              _hechos = h;
              _total = t;
            });
          }
        },
      );
      if (!mounted) return;
      if (r.movimientos > 0 || r.itemsCreados > 0) {
        final partes = <String>[
          '${r.movimientos} movimientos',
          if (r.itemsCreados > 0) '${r.itemsCreados} ítems nuevos',
          if (r.repetidos > 0) '${r.repetidos} repetidos omitidos',
          if (r.fallidos > 0) '${r.fallidos} con problemas',
        ];
        mostrarExito(context, 'Importado: ${partes.join(' · ')}.');
        Navigator.pop(context, true);
      } else {
        setState(() {
          _importando = false;
          _error = r.primerError != null
              ? 'No se pudo importar: ${r.primerError}'
              : (r.repetidos > 0
                  ? 'Todos los movimientos ya estaban importados.'
                  : 'No se importó ningún movimiento.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nItems = _lecturaItems?.nuevas.length ?? 0;
    final nMovs = _lecturaMov?.importables.length ?? 0;
    final n = _esItems ? nItems : nMovs;

    return ModalFormulario(
      titulo: 'Importar Excel',
      icono: Icons.upload_file,
      ancho: 660,
      guardando: _leyendo || _importando,
      textoBoton: !_hayLectura
          ? 'Elegir archivo Excel (.xlsx)'
          : (_esItems ? 'Importar $n ítems' : 'Importar $n movimientos'),
      onGuardar: !_hayLectura ? _elegirArchivo : (n > 0 ? _importar : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SeccionFormulario('Inventario de ${widget.area.etiqueta}'),
          const SizedBox(height: 6),
          if (!_hayLectura)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'items',
                    icon: Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text('Ítems')),
                ButtonSegment(
                    value: 'movimientos',
                    icon: Icon(Icons.swap_vert, size: 18),
                    label: Text('Movimientos')),
              ],
              selected: {_modo},
              onSelectionChanged: (s) => _cambiarModo(s.first),
            ),
          if (!_hayLectura) ...(_esItems ? _pasoElegirItems() : _pasoElegirMov()),
          if (_hayLectura) ...(_esItems ? _revisarItems(_lecturaItems!) : _revisarMov(_lecturaMov!)),
          if (_leyendo && _hayLectura == false)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(color: AppColors.primario),
            ),
          if (_importando) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _total == 0 ? null : _hechos / _total,
              color: AppColors.primario,
            ),
            const SizedBox(height: 4),
            Text('Importando... $_hechos de $_total',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEA),
                border: Border.all(color: const Color(0xFFF5C2BE)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonPlantilla() => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _descargarPlantilla,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Descargar plantilla de Excel'),
        ),
      );

  List<Widget> _pasoElegirItems() => [
        const SizedBox(height: 12),
        const Text(
          'Da de alta el catálogo desde un Excel (.xlsx). Las columnas se '
          'reconocen por su nombre (Detalle, Formato, Color/Tamaño, Unidad, '
          'Cantidad, Stock mínimo, Proveedor); solo "Detalle" es obligatorio. '
          'El código lo genera el sistema y los ítems que ya existen se omiten '
          '(nunca se duplican ni se modifican).',
          style: TextStyle(fontSize: 13, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si tu Excel repite el mismo ítem porque son compras o consumos '
          'distintos, importalo como "Movimientos": así cada fila queda en el '
          'historial y el ítem se crea una sola vez.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        _botonPlantilla(),
      ];

  List<Widget> _pasoElegirMov() => [
        const SizedBox(height: 12),
        const Text(
          'Carga el historial de entradas, salidas y ajustes desde tu Excel. '
          'Cada fila se asocia a su ítem por Código o Detalle; el mismo ítem '
          'puede aparecer todas las veces que haga falta. Volver a importar el '
          'mismo archivo (o uno que repita filas) no duplica nada.',
          style: TextStyle(fontSize: 13, color: Colors.black87),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _crearItems,
          activeThumbColor: AppColors.primario,
          onChanged: (v) => setState(() => _crearItems = v),
          title: const Text('Crear los ítems que no existan'),
          subtitle: const Text('Se crean una sola vez, aunque tengan muchas filas.',
              style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 4),
        _selectorEfectoStock(),
        const SizedBox(height: 12),
        _botonPlantilla(),
      ];

  Widget _selectorEfectoStock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Efecto en el stock',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Solo historial')),
              ButtonSegment(value: false, label: Text('Aplicar al stock')),
            ],
            selected: {_soloHistorial},
            onSelectionChanged: (s) => setState(() => _soloHistorial = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _soloHistorial
                ? 'Los movimientos quedan en el historial pero NO cambian el stock '
                    '(usalo si el stock actual ya está cargado).'
                : 'Además de quedar en el historial, suman o restan del stock actual '
                    '(usalo para ítems nuevos o si el stock parte de cero).',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );

  Widget _encabezadoArchivo() => Row(
        children: [
          Expanded(
            child: Text(_nombreArchivo ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: _importando
                ? null
                : () => setState(() {
                      _lecturaItems = null;
                      _lecturaMov = null;
                      _bytes = null;
                      _error = null;
                    }),
            child: const Text('Elegir otro'),
          ),
        ],
      );

  List<Widget> _revisarItems(ResultadoLectura l) => [
        const SizedBox(height: 8),
        _encabezadoArchivo(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Resumen('${l.nuevas.length} nuevos', AppColors.primario, Icons.add_circle_outline),
            _Resumen('${l.repetidas.length} repetidos (se omiten)',
                const Color(0xFFD97706), Icons.copy_all_outlined),
            _Resumen('${l.conError.length} con error', const Color(0xFFDC2626),
                Icons.error_outline),
          ],
        ),
        const SizedBox(height: 8),
        Text('Columnas reconocidas: ${l.columnasReconocidas.join(', ')}',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 10),
        _lista([
          for (final f in l.filas)
            _ItemLista(
              titulo: f.detalle,
              detalle: f.esNueva
                  ? 'Fila ${f.fila} · se creará con ${_num(f.insumo!.cantidadReal)} ${f.insumo!.unidadMedida}'
                  : 'Fila ${f.fila} · ${f.error ?? f.repetido}',
              estado: f.esNueva ? _Estado.ok : (f.error != null ? _Estado.error : _Estado.aviso),
            ),
        ]),
      ];

  List<Widget> _revisarMov(ResultadoLecturaMov l) {
    const etiquetaTipo = {'ingreso': 'Entrada', 'salida': 'Salida', 'ajuste': 'Ajuste'};
    return [
      const SizedBox(height: 8),
      _encabezadoArchivo(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _crearItems,
        activeThumbColor: AppColors.primario,
        onChanged: _importando
            ? null
            : (v) async {
                setState(() => _crearItems = v);
                await _procesar();
              },
        title: const Text('Crear los ítems que no existan'),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Resumen('${l.importables.length} movimientos', AppColors.primario,
              Icons.swap_vert),
          if (l.itemsPorCrear.isNotEmpty)
            _Resumen('${l.itemsPorCrear.length} ítems nuevos', const Color(0xFF2563EB),
                Icons.add_box_outlined),
          _Resumen('${l.yaImportadas.length} ya importados (se omiten)',
              const Color(0xFFD97706), Icons.copy_all_outlined),
          _Resumen('${l.conError.length} con error', const Color(0xFFDC2626),
              Icons.error_outline),
        ],
      ),
      const SizedBox(height: 8),
      Text('Columnas reconocidas: ${l.columnasReconocidas.join(', ')}',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 10),
      _selectorEfectoStock(),
      const SizedBox(height: 10),
      _lista([
        for (final f in l.filas)
          _ItemLista(
            titulo: f.etiquetaItem,
            detalle: f.error != null
                ? 'Fila ${f.fila} · ${f.error}'
                : (f.yaImportado
                    ? 'Fila ${f.fila} · ya se importó antes (se omite)'
                    : 'Fila ${f.fila} · ${etiquetaTipo[f.tipo] ?? f.tipo} '
                        '${f.tipo == 'ingreso' ? '+' : (f.tipo == 'salida' ? '-' : '±')}'
                        '${_num(f.cantidad)}'
                        '${f.unidad != null ? ' ${f.unidad}' : ''}'
                        '${f.fecha != null ? ' · ${fmtFecha(f.fecha)}' : ' · sin fecha (hoy)'}'
                        '${f.itemNuevo != null ? ' · ítem nuevo' : ''}'),
            estado: f.error != null
                ? _Estado.error
                : (f.yaImportado ? _Estado.aviso : _Estado.ok),
          ),
      ]),
    ];
  }

  static String _num(double n) => n % 1 == 0 ? n.toInt().toString() : n.toString();

  Widget _lista(List<_ItemLista> items) => Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final it = items[i];
            final color = switch (it.estado) {
              _Estado.ok => AppColors.primario,
              _Estado.aviso => const Color(0xFFD97706),
              _Estado.error => const Color(0xFFDC2626),
            };
            return ListTile(
              dense: true,
              leading: Icon(
                  switch (it.estado) {
                    _Estado.ok => Icons.check_circle_outline,
                    _Estado.aviso => Icons.copy_all_outlined,
                    _Estado.error => Icons.error_outline,
                  },
                  color: color,
                  size: 20),
              title: Text(it.titulo, overflow: TextOverflow.ellipsis),
              subtitle: Text(it.detalle,
                  style: TextStyle(
                      fontSize: 12,
                      color: it.estado == _Estado.ok ? Colors.black54 : color)),
            );
          },
        ),
      );
}

enum _Estado { ok, aviso, error }

class _ItemLista {
  final String titulo;
  final String detalle;
  final _Estado estado;
  const _ItemLista({required this.titulo, required this.detalle, required this.estado});
}

class _Resumen extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData icono;
  const _Resumen(this.texto, this.color, this.icono);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 6),
          Text(texto,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
