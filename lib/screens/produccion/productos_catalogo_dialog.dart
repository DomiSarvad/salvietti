import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../shared/pagina_o_dialogo.dart';
import '../../utils/formatters.dart';
import '../../models/insumo.dart';
import '../../models/produccion.dart';
import '../../services/inventario_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/responsive.dart';

/// Catálogo de productos embotellados (sabor + tamaño + envase, ej.
/// "2,5 L Papaya - Pett"), tal como los nombran en el reporte que
/// comparten por WhatsApp. Cada uno define qué preforma y qué tapa
/// consume por botella, para que al marcar la producción como hecha el
/// sistema sepa exactamente qué descontar.
class ProductosCatalogoDialog extends StatefulWidget {
  const ProductosCatalogoDialog({super.key});

  @override
  State<ProductosCatalogoDialog> createState() => _ProductosCatalogoDialogState();
}

class _ProductosCatalogoDialogState extends State<ProductosCatalogoDialog> {
  List<ProductoTerminado> _productos = [];
  List<Formula> _formulas = [];
  List<Insumo> _preformas = [];
  List<Insumo> _tapas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resultados = await Future.wait([
      ProduccionService.listarProductosTerminados(),
      ProduccionService.listarFormulas(),
      InventarioService.listar('preformas'),
      InventarioService.listar('tapas'),
    ]);
    if (!mounted) return;
    setState(() {
      _productos = resultados[0] as List<ProductoTerminado>;
      _formulas = resultados[1] as List<Formula>;
      _preformas = resultados[2] as List<Insumo>;
      _tapas = resultados[3] as List<Insumo>;
      _cargando = false;
    });
  }

  String _sabor(String formulaId) =>
      _formulas.firstWhere((f) => f.id == formulaId, orElse: () => Formula(id: '', sabor: '?', rendimientoLitros: 1)).sabor;

  /// Sin [producto]: alta. Con producto: la misma ficha para editarlo.
  Future<void> _abrirProducto([ProductoTerminado? producto]) async {
    final guardado = await abrirAdaptable<bool>(
      context,
      (_) => _NuevoProductoDialog(
          formulas: _formulas, preformas: _preformas, tapas: _tapas, producto: producto),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return DialogoAdaptable(
      titulo: 'Catálogo de productos',
      ancho: anchoDialogo(context, 480),
      alto: 420,
      desplazar: false,
      contenido: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _formulas.isEmpty
                ? const Center(
                    child: Text('Primero necesitas al menos una fórmula/sabor '
                        'creada para poder armar productos.'))
                : ListView.separated(
                    itemCount: _productos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _productos[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _FotoProducto(url: p.fotoUrl, tamano: 48),
                        title: Text(p.nombre),
                        subtitle: Text(
                            '${_sabor(p.formulaId)} · ${p.envase == 'pett' ? 'PET' : 'Vidrio'} · '
                            '${fmtNum(p.litrosPorBotella, decimales: 2)} L/botella'),
                        trailing: const Icon(Icons.chevron_right),
                        // Tocar abre la ficha para cambiar nombre, materiales o foto.
                        onTap: () => _abrirProducto(p),
                      );
                    },
                  ),
      acciones: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
        if (_formulas.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _abrirProducto(),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo producto'),
          ),
      ],
    );
  }
}

/// Foto del producto (o un ícono si no tiene).
class _FotoProducto extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final double tamano;
  const _FotoProducto({this.url, this.bytes, required this.tamano});

  @override
  Widget build(BuildContext context) {
    final vacio = Container(
      width: tamano,
      height: tamano,
      color: AppColors.primario.withValues(alpha: 0.08),
      child: Icon(Icons.local_drink_outlined, color: AppColors.primario, size: tamano * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: bytes != null
          ? Image.memory(bytes!, width: tamano, height: tamano, fit: BoxFit.cover)
          : url == null
              ? vacio
              : Image.network(url!,
                  width: tamano, height: tamano, fit: BoxFit.cover, errorBuilder: (_, __, ___) => vacio),
    );
  }
}

class _NuevoProductoDialog extends StatefulWidget {
  final List<Formula> formulas;
  final List<Insumo> preformas;
  final List<Insumo> tapas;

  /// Con producto: se edita ese (nombre, materiales, litros, foto).
  final ProductoTerminado? producto;
  const _NuevoProductoDialog(
      {required this.formulas, required this.preformas, required this.tapas, this.producto});

  @override
  State<_NuevoProductoDialog> createState() => _NuevoProductoDialogState();
}

class _NuevoProductoDialogState extends State<_NuevoProductoDialog> {
  final _nombreCtrl = TextEditingController();
  final _nombreFocusNode = FocusNode();
  bool _nombreEditadoManualmente = false;
  final _litrosBotellaCtrl = TextEditingController();
  final _botellasPaqueteCtrl = TextEditingController();
  Formula? _formula;
  String _envase = 'pett';
  Insumo? _preforma;
  Insumo? _tapa;
  bool _guardando = false;
  String? _error;

  /// Foto nueva elegida (todavía sin subir) y la que ya tenía.
  Uint8List? _fotoBytes;
  String _fotoExt = 'jpg';
  String? _fotoUrl;

  /// Lo que gasta la receta del sabor: (insumo, cantidad por lote, unidad).
  List<(String, double, String)> _consumo = [];

  bool get _editando => widget.producto != null;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    if (p != null) {
      _nombreEditadoManualmente = true; // el nombre ya existe: no se pisa
      _nombreCtrl.text = p.nombre;
      _formula = widget.formulas.where((f) => f.id == p.formulaId).firstOrNull;
      _envase = p.envase;
      _litrosBotellaCtrl.text = _numero(p.litrosPorBotella);
      if (p.botellasPorPaquete != null) _botellasPaqueteCtrl.text = _numero(p.botellasPorPaquete!);
      _preforma = widget.preformas.where((i) => i.id == p.preformaId).firstOrNull;
      _tapa = widget.tapas.where((i) => i.id == p.tapaId).firstOrNull;
      _fotoUrl = p.fotoUrl;
      _cargarConsumo();
    }
  }

  static String _numero(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  Future<void> _cargarConsumo() async {
    final f = _formula;
    if (f == null) {
      setState(() => _consumo = []);
      return;
    }
    final detalle = await ProduccionService.listarFormulaDetalle(f.id);
    if (!mounted || _formula?.id != f.id) return;
    setState(() => _consumo = [
          for (final d in detalle)
            (
              ((d['materia_prima'] as Map?)?['detalle'] as String?) ?? '—',
              (d['cantidad_por_lote'] as num).toDouble(),
              ((d['materia_prima'] as Map?)?['unidad_medida'] as String?) ?? '',
            )
        ]);
  }

  Future<void> _elegirFoto() async {
    try {
      final r = await FilePicker.pickFiles(type: FileType.image, withData: true);
      final a = r?.files.firstOrNull;
      if (a?.bytes == null) return;
      setState(() {
        _fotoBytes = a!.bytes;
        _fotoExt = (a.extension ?? 'jpg').toLowerCase();
      });
    } catch (_) {
      setState(() => _error = 'No se pudo abrir el selector de fotos.');
    }
  }

  @override
  void dispose() {
    _nombreFocusNode.dispose();
    super.dispose();
  }

  /// Arma el nombre solo mientras el usuario no lo haya tocado a mano
  /// (se detecta por si el campo tiene el foco cuando cambia el texto:
  /// un cambio programático, como este, nunca ocurre con el campo
  /// enfocado por el usuario).
  void _sugerirNombre() {
    if (_nombreEditadoManualmente) return;
    final litros = double.tryParse(_litrosBotellaCtrl.text);
    final partes = <String>[];
    if (litros != null && litros > 0) {
      partes.add(litros < 1
          ? '${(litros * 1000).round()} ml'
          : '${litros == litros.roundToDouble() ? litros.toStringAsFixed(0) : litros.toString().replaceAll('.', ',')} L');
    }
    if (_formula != null) partes.add(_formula!.sabor);
    if (partes.isEmpty) {
      _nombreCtrl.text = '';
      return;
    }
    _nombreCtrl.text = '${partes.join(' ')} - ${_envase == 'pett' ? 'Pett' : 'Vidrio'}';
  }

  Future<void> _guardar() async {
    final litrosBotella = double.tryParse(_litrosBotellaCtrl.text);
    if (_nombreCtrl.text.trim().isEmpty ||
        _formula == null ||
        litrosBotella == null ||
        litrosBotella <= 0 ||
        _tapa == null ||
        (_envase == 'pett' && _preforma == null)) {
      setState(() => _error = 'Completa nombre, fórmula, litros por botella, '
          'tapa${_envase == 'pett' ? ' y preforma' : ''}.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      var foto = _fotoUrl;
      if (_fotoBytes != null) {
        foto = await ProduccionService.subirFotoProducto(_fotoBytes!, _fotoExt);
      }
      final producto = ProductoTerminado(
        id: widget.producto?.id ?? '',
        nombre: _nombreCtrl.text.trim(),
        formulaId: _formula!.id,
        envase: _envase,
        litrosPorBotella: litrosBotella,
        botellasPorPaquete: double.tryParse(_botellasPaqueteCtrl.text),
        preformaId: _envase == 'pett' ? _preforma!.id : null,
        tapaId: _tapa!.id,
        fotoUrl: foto,
      );
      _editando
          ? await ProduccionService.actualizarProductoTerminado(producto)
          : await ProduccionService.guardarProductoTerminado(producto);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Guardar producto: $e');
      setState(() => _error = _fotoBytes != null && e.toString().contains('torage')
          ? 'No se pudo subir la foto (¿se ejecutó la migración v46?).'
          : 'No se pudo guardar. Revisá la conexión e intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final litros = double.tryParse(_litrosBotellaCtrl.text);
    final rinde = _formula?.rendimientoLitros;
    return DialogoAdaptable(
      titulo: _editando ? 'Editar producto' : 'Nuevo producto',
      ancho: anchoDialogo(context, 400),
      contenido: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Foto: tocarla para elegir o cambiar.
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _elegirFoto,
                  child: Stack(children: [
                    _FotoProducto(url: _fotoUrl, bytes: _fotoBytes, tamano: 110),
                    const Positioned(
                      right: 4,
                      bottom: 4,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primario,
                        child: Icon(Icons.photo_camera_outlined, size: 16, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nombreCtrl,
                focusNode: _nombreFocusNode,
                onChanged: (_) {
                  if (_nombreFocusNode.hasFocus) _nombreEditadoManualmente = true;
                },
                decoration: const InputDecoration(
                    labelText: 'Nombre (se arma solo; podés editarlo)'),
              ),
              DropdownButtonFormField<Formula>(
                value: _formula,
                decoration: const InputDecoration(labelText: 'Sabor'),
                items: widget.formulas
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.sabor)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _formula = v;
                    _sugerirNombre();
                  });
                  _cargarConsumo();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pett', label: Text('PET (preforma)')),
                      ButtonSegment(value: 'vidrio', label: Text('Vidrio')),
                    ],
                    selected: {_envase},
                    onSelectionChanged: (s) => setState(() {
                      _envase = s.first;
                      if (_envase == 'vidrio') _preforma = null;
                      _sugerirNombre();
                    }),
                  ),
                ),
              ),
              TextField(
                controller: _litrosBotellaCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Litros por botella'),
                onChanged: (_) => setState(_sugerirNombre),
              ),
              TextField(
                controller: _botellasPaqueteCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Botellas por paquete/caja (opcional)'),
              ),
              if (_envase == 'pett')
                _BuscadorInsumo(
                  label: 'Preforma',
                  opciones: widget.preformas,
                  inicial: _preforma,
                  onSelected: (p) => setState(() => _preforma = p),
                ),
              _BuscadorInsumo(
                label: 'Tapa',
                opciones: widget.tapas,
                inicial: _tapa,
                onSelected: (t) => setState(() => _tapa = t),
              ),
              // Cuánto gasta cada botella: la receta del sabor llevada a los
              // litros de esta botella, más su preforma y su tapa.
              if (_formula != null) ...[
                const SizedBox(height: 16),
                const Text('Consumo por botella',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (_consumo.isEmpty)
                  const Text('Este sabor todavía no tiene receta cargada ("Editar consumo").',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54))
                else
                  for (final (insumo, porLote, unidad) in _consumo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(insumo, style: const TextStyle(fontSize: 13))),
                        Text(
                          litros != null && litros > 0 && (rinde ?? 0) > 0
                              ? '${fmtNum(porLote / rinde! * litros, decimales: 4)} $unidad'
                              : '${fmtNum(porLote)} $unidad por lote',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                if (_envase == 'pett' && _preforma != null)
                  Text('1 preforma: ${_preforma!.detalle}', style: const TextStyle(fontSize: 13)),
                if (_tapa != null)
                  Text('1 tapa: ${_tapa!.detalle}', style: const TextStyle(fontSize: 13)),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
      acciones: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Buscador de un insumo (preforma o tapa): escribís y filtra por código
/// o detalle, igual que el selector de insumo en "Registrar movimiento".
class _BuscadorInsumo extends StatelessWidget {
  final String label;
  final List<Insumo> opciones;
  final Insumo? inicial;
  final ValueChanged<Insumo> onSelected;
  const _BuscadorInsumo(
      {required this.label, required this.opciones, required this.onSelected, this.inicial});

  static String _texto(Insumo i) => '${i.codigo} · ${i.detalle}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Insumo>(
      initialValue: inicial == null ? null : TextEditingValue(text: _texto(inicial!)),
      displayStringForOption: _texto,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return opciones;
        return opciones.where((i) =>
            i.detalle.toLowerCase().contains(q) ||
            i.codigo.toLowerCase().contains(q));
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Buscar por código o nombre...',
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
        );
      },
    );
  }
}
