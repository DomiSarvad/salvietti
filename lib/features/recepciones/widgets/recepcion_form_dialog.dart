import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../utils/texto.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/recepciones_modelos.dart';
import '../services/recepciones_service.dart';

/// Formulario de una recepción nueva. Solo recoge datos; el service valida,
/// convierte unidades y guarda. Devuelve `true` si se guardó.
class RecepcionFormDialog extends StatefulWidget {
  final RecepcionesService servicio;
  const RecepcionFormDialog({super.key, required this.servicio});

  @override
  State<RecepcionFormDialog> createState() => _RecepcionFormDialogState();
}

class _RecepcionFormDialogState extends State<RecepcionFormDialog> {
  late String _almacenId;
  List<ItemRecepcion> _items = [];
  List<Proveedor> _proveedores = [];
  bool _cargandoDatos = true;

  ItemRecepcion? _item;
  Proveedor? _proveedor;
  String _textoProveedor = '';
  DateTime _fecha = DateTime.now();
  DateTime? _fabricacion;
  DateTime? _vencimiento;
  String _unidad = 'UNI';
  FotoAdjunta? _foto;

  bool _senasacAuto = false;
  bool _guardando = false;
  String? _error;

  final _factura = TextEditingController();
  final _cantFactura = TextEditingController();
  final _cantReal = TextEditingController();
  final _lote = TextEditingController();
  final _senasac = TextEditingController();
  final _transportador = TextEditingController();
  final _precio = TextEditingController();
  final _obs = TextEditingController();

  RecepcionesService get _svc => widget.servicio;

  @override
  void initState() {
    super.initState();
    _almacenId = _svc.almacenes
        .firstWhere((a) => _svc.puedeRecibirEn(a.id), orElse: () => _svc.almacenes.first)
        .id;
    _cargarDatos();
  }

  @override
  void dispose() {
    for (final c in [_factura, _cantFactura, _cantReal, _lote, _senasac, _transportador, _precio, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargandoDatos = true);
    try {
      final r = await Future.wait([_svc.itemsDe(_almacenId), _svc.proveedores()]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<ItemRecepcion>;
        _proveedores = r[1] as List<Proveedor>;
        _cargandoDatos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoDatos = false;
        _error = 'No se pudieron cargar los ítems. Revisá la conexión.';
      });
    }
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  List<String> get _unidades {
    final u = _item?.unidad;
    if (u == 'KG') return const ['KG', 'GR'];
    if (u == 'L') return const ['L', 'ML'];
    return [u ?? 'UNI'];
  }

  BorradorRecepcion _borrador() => BorradorRecepcion(
        almacenId: _almacenId,
        item: _item,
        proveedor: _proveedor,
        fecha: _fecha,
        unidadEntrada: _unidad,
        cantidadFactura: _num(_cantFactura),
        cantidadReal: _num(_cantReal),
        nFactura: _factura.text,
        nLote: _lote.text,
        fechaFabricacion: _fabricacion,
        fechaVencimiento: _vencimiento,
        senasac: _senasac.text,
        transportador: _transportador.text,
        precioTransporte: _num(_precio),
        observaciones: _obs.text,
        foto: _foto,
      );

  /// Completa el SENASAG si ya se conoce para ese producto y proveedor, sin
  /// pisar lo que la persona escribió.
  Future<void> _sugerirSenasac() async {
    final item = _item;
    final prov = _proveedor;
    if (item == null || prov == null) return;
    final s = await _svc.senasacSugerido(item.id, prov.id);
    if (!mounted || s == null) return;
    if (_senasac.text.trim().isEmpty || _senasacAuto) {
      setState(() {
        _senasac.text = s;
        _senasacAuto = true;
      });
    }
  }

  Future<void> _elegirFecha({
    required DateTime? actual,
    required void Function(DateTime) alElegir,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final ahora = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: actual ?? ahora,
      firstDate: desde ?? DateTime(ahora.year - 3),
      lastDate: hasta ?? DateTime(ahora.year + 6),
    );
    if (d != null) setState(() => alElegir(d));
  }

  Future<void> _elegirFoto() async {
    try {
      final r = await FilePicker.pickFiles(
        dialogTitle: 'Foto de la factura o de la etiqueta',
        type: FileType.image,
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final a = r.files.first;
      if (a.bytes == null) {
        setState(() => _error = 'No se pudo leer la foto elegida.');
        return;
      }
      setState(() {
        _foto = FotoAdjunta(bytes: a.bytes!, nombre: a.name);
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo abrir el selector de fotos.');
    }
  }

  Future<void> _crearProveedor() async {
    final p = await _svc.crearProveedor(_textoProveedor);
    if (!mounted) return;
    if (p == null) {
      setState(() => _error = 'No se pudo crear el proveedor (2 a 80 caracteres).');
      return;
    }
    setState(() {
      if (!_proveedores.any((x) => x.id == p.id)) _proveedores = [..._proveedores, p];
      _proveedor = p;
      _textoProveedor = p.nombre;
      _error = null;
    });
    _sugerirSenasac();
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await _svc.guardar(_borrador());
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Recepción registrada.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label, {String? ayuda, Widget? sufijo}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        helperMaxLines: 2,
        suffixIcon: sufijo,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _texto(TextEditingController c, String label,
          {String? ayuda, bool numerico = false, int? max, VoidCallback? alCambiar}) =>
      TextField(
        controller: c,
        maxLength: max,
        onChanged: (_) {
          alCambiar?.call();
          setState(() {});
        },
        keyboardType: numerico
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: _deco(label, ayuda: ayuda).copyWith(counterText: ''),
      );

  Widget _fechaCampo(String etiqueta, DateTime? valor, VoidCallback onTap, {VoidCallback? borrar}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: _deco(
            etiqueta,
            sufijo: borrar != null && valor != null
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: borrar)
                : const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(valor == null ? '—' : fmtFecha(valor)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dif = RecepcionesService.diferenciaDe(_borrador());
    final unidadItem = _item?.unidad ?? '';
    final coincidencias = _proveedores
        .where((p) => sinTildes(p.nombre) == sinTildes(_textoProveedor.trim()))
        .isNotEmpty;
    const sep = SizedBox(height: 12);

    return ModalFormulario(
      titulo: 'Nueva recepción',
      icono: Icons.local_shipping_outlined,
      textoBoton: 'Registrar recepción',
      guardando: _guardando,
      onGuardar: _cargandoDatos ? null : _guardar,
      ancho: 560,
      child: _cargandoDatos
          ? const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_svc.almacenes.where((a) => _svc.puedeRecibirEn(a.id)).length > 1) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _almacenId,
                    decoration: _deco('Almacén'),
                    items: [
                      for (final a in _svc.almacenes.where((a) => _svc.puedeRecibirEn(a.id)))
                        DropdownMenuItem(value: a.id, child: Text(a.nombre)),
                    ],
                    onChanged: (v) {
                      if (v == null || v == _almacenId) return;
                      setState(() {
                        _almacenId = v;
                        _item = null;
                      });
                      _cargarDatos();
                    },
                  ),
                  sep,
                ],
                Autocomplete<ItemRecepcion>(
                  displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
                  optionsBuilder: (t) {
                    final q = sinTildes(t.text.trim());
                    final lista = q.isEmpty
                        ? _items
                        : _items.where((i) =>
                            sinTildes(i.detalle).contains(q) || sinTildes(i.codigo).contains(q));
                    return lista.take(30);
                  },
                  onSelected: (i) {
                    setState(() {
                      _item = i;
                      _unidad = i.unidad;
                      _senasacAuto = false;
                    });
                    _sugerirSenasac();
                  },
                  fieldViewBuilder: (context, c, foco, _) => TextField(
                    controller: c,
                    focusNode: foco,
                    onChanged: (t) {
                      if (_item != null &&
                          t != '${_item!.codigo} · ${_item!.detalle}') {
                        setState(() => _item = null);
                      }
                    },
                    decoration: _deco('Ítem que llegó',
                        ayuda: _item == null ? 'Escribí para buscar por nombre o código' : null,
                        sufijo: const Icon(Icons.search, size: 18)),
                  ),
                ),
                sep,
                Autocomplete<Proveedor>(
                  displayStringForOption: (p) => p.nombre,
                  optionsBuilder: (t) {
                    final q = sinTildes(t.text.trim());
                    return _proveedores
                        .where((p) => q.isEmpty || sinTildes(p.nombre).contains(q))
                        .take(20);
                  },
                  onSelected: (p) {
                    setState(() {
                      _proveedor = p;
                      _textoProveedor = p.nombre;
                      _senasacAuto = false;
                    });
                    _sugerirSenasac();
                  },
                  fieldViewBuilder: (context, c, foco, _) => TextField(
                    controller: c,
                    focusNode: foco,
                    onChanged: (t) => setState(() {
                      _textoProveedor = t;
                      if (_proveedor != null && t != _proveedor!.nombre) _proveedor = null;
                    }),
                    decoration: _deco('Proveedor', sufijo: const Icon(Icons.search, size: 18)),
                  ),
                ),
                if (_textoProveedor.trim().length >= 2 && !coincidencias && _proveedor == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _crearProveedor,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Crear proveedor "${_textoProveedor.trim()}"'),
                    ),
                  ),
                sep,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _texto(_factura, 'N° de factura', max: 40)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _fechaCampo(
                        'Fecha de recepción',
                        _fecha,
                        () => _elegirFecha(
                          actual: _fecha,
                          alElegir: (d) => _fecha = d,
                          hasta: DateTime.now(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Cantidades', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _texto(_cantFactura, 'Según factura / etiqueta',
                            numerico: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _texto(_cantReal, 'Real (pesado)', numerico: true)),
                    const SizedBox(width: 10),
                    if (_unidades.length > 1)
                      SizedBox(
                        width: 78,
                        child: DropdownButtonFormField<String>(
                          initialValue: _unidad,
                          decoration: _deco('Unidad'),
                          items: [
                            for (final u in _unidades) DropdownMenuItem(value: u, child: Text(u)),
                          ],
                          onChanged: (v) => setState(() => _unidad = v ?? _unidad),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(unidadItem,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                if (dif != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      dif.abs() < 1e-9
                          ? 'Llegó completo: sin diferencia.'
                          : (dif < 0
                              ? 'Faltan ${fmtNum(-dif, decimales: 3)} $unidadItem respecto de la factura '
                                  '(queda para el reclamo).'
                              : 'Sobran ${fmtNum(dif, decimales: 3)} $unidadItem respecto de la factura.'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: dif.abs() < 1e-9
                            ? const Color(0xFF16A34A)
                            : (dif < 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706)),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Lote y vencimiento', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _texto(_lote, 'N° de lote', max: 40),
                sep,
                Row(
                  children: [
                    Expanded(
                      child: _fechaCampo(
                        'Fabricación',
                        _fabricacion,
                        () => _elegirFecha(
                            actual: _fabricacion,
                            alElegir: (d) => _fabricacion = d,
                            hasta: DateTime.now()),
                        borrar: () => setState(() => _fabricacion = null),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _fechaCampo(
                        'Vencimiento',
                        _vencimiento,
                        () => _elegirFecha(
                            actual: _vencimiento, alElegir: (d) => _vencimiento = d),
                        borrar: () => setState(() => _vencimiento = null),
                      ),
                    ),
                  ],
                ),
                sep,
                _texto(
                  _senasac,
                  'SENASAG (ficha técnica)',
                  max: 40,
                  ayuda: _senasacAuto
                      ? 'Completado solo: ya se conocía para este producto y proveedor.'
                      : 'Si lo escribís una vez, el sistema lo recuerda.',
                  alCambiar: () => _senasacAuto = false,
                ),
                const SizedBox(height: 16),
                const Text('Transporte', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _texto(_transportador, 'Transportador', max: 80)),
                    const SizedBox(width: 10),
                    Expanded(child: _texto(_precio, 'Precio (Bs)', numerico: true)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Respaldo', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_foto == null)
                  OutlinedButton.icon(
                    onPressed: _elegirFoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Adjuntar foto de la factura o etiqueta'),
                  )
                else
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_foto!.bytes, width: 72, height: 72, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(_foto!.nombre, overflow: TextOverflow.ellipsis)),
                      IconButton(
                        tooltip: 'Quitar foto',
                        onPressed: () => setState(() => _foto = null),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                sep,
                TextField(
                  controller: _obs,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: _deco('Observaciones (opcional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
                ],
              ],
            ),
    );
  }
}
