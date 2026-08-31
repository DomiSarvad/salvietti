import 'package:flutter/material.dart';
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

  Future<void> _nuevoProducto() async {
    final creado = await showDialog<bool>(
      context: context,
      builder: (_) => _NuevoProductoDialog(
          formulas: _formulas, preformas: _preformas, tapas: _tapas),
    );
    if (creado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catálogo de productos'),
      content: SizedBox(
        width: anchoDialogo(context, 480),
        height: 420,
        child: _cargando
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
                        title: Text(p.nombre),
                        subtitle: Text(
                            '${_sabor(p.formulaId)} · ${p.envase == 'pett' ? 'PET' : 'Vidrio'} · '
                            '${p.litrosPorBotella} L/botella'),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
        if (_formulas.isNotEmpty)
          FilledButton.icon(
            onPressed: _nuevoProducto,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo producto'),
          ),
      ],
    );
  }
}

class _NuevoProductoDialog extends StatefulWidget {
  final List<Formula> formulas;
  final List<Insumo> preformas;
  final List<Insumo> tapas;
  const _NuevoProductoDialog(
      {required this.formulas, required this.preformas, required this.tapas});

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
      await ProduccionService.guardarProductoTerminado(ProductoTerminado(
        id: '',
        nombre: _nombreCtrl.text.trim(),
        formulaId: _formula!.id,
        envase: _envase,
        litrosPorBotella: litrosBotella,
        botellasPorPaquete: double.tryParse(_botellasPaqueteCtrl.text),
        preformaId: _envase == 'pett' ? _preforma!.id : null,
        tapaId: _tapa!.id,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo producto'),
      content: SizedBox(
        width: anchoDialogo(context, 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                onChanged: (v) => setState(() {
                  _formula = v;
                  _sugerirNombre();
                }),
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
                  onSelected: (p) => setState(() => _preforma = p),
                ),
              _BuscadorInsumo(
                label: 'Tapa',
                opciones: widget.tapas,
                onSelected: (t) => setState(() => _tapa = t),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
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
  final ValueChanged<Insumo> onSelected;
  const _BuscadorInsumo(
      {required this.label, required this.opciones, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Insumo>(
      displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
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
