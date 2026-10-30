import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../shared/aviso_campo.dart';
import '../../../shared/alertas.dart';
import '../../../core/constants.dart';
import '../../../shared/busqueda_local.dart';
import '../../../utils/formatters.dart';
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
  // Índice en memoria: el texto de cada ítem se normaliza una vez, no por letra.
  IndiceBusqueda<ItemRecepcion> _items = IndiceBusqueda(const [], _textoItem);

  static String _textoItem(ItemRecepcion i) => '${i.codigo} ${i.detalle}';
  List<Proveedor> _proveedores = [];
  bool _cargandoDatos = true;

  ItemRecepcion? _item;
  Proveedor? _proveedor;
  String _textoProveedor = '';
  DateTime _fecha = DateTime.now();
  DateTime? _fabricacion;
  DateTime? _vencimiento;
  String _unidad = 'UNI';
  final List<FotoAdjunta> _fotos = [];

  bool _senasacAuto = false;
  bool _guardando = false;
  String? _error;

  /// Factura con varios ítems: al guardar, el formulario queda abierto con el
  /// proveedor, la factura y la fecha, listo para el siguiente ítem.
  bool _otraMas = false;

  /// Lo registrado en esta sesión (ítem y cantidad real en su unidad), para
  /// poder entregarlo a un área en un solo paso.
  final _registradas = <(ItemRecepcion, double)>[];

  /// Cambia para vaciar el buscador de ítem (Autocomplete guarda su texto).
  int _versionItem = 0;

  /// Una clave por campo, para señalar con un globo el que falta o está mal.
  final _claves = {for (final c in CampoRecepcion.values) c: GlobalKey()};
  Widget _campo(CampoRecepcion c, Widget hijo) => KeyedSubtree(key: _claves[c], child: hijo);

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
        _items = IndiceBusqueda(r[0] as List<ItemRecepcion>, _textoItem);
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
        fotos: List.of(_fotos),
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
        dialogTitle: 'Fotos de la factura o de la etiqueta',
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final leidas = [
        for (final a in r.files)
          if (a.bytes != null) FotoAdjunta(bytes: a.bytes!, nombre: a.name)
      ];
      final lugar = RecepcionesService.maxFotos - _fotos.length;
      setState(() {
        _fotos.addAll(leidas.take(lugar));
        _error = leidas.length < r.files.length
            ? 'No se pudo leer alguna de las fotos elegidas.'
            : leidas.length > lugar
                ? 'Se pueden adjuntar hasta ${RecepcionesService.maxFotos} fotos.'
                : null;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo abrir el selector de fotos.');
    }
  }

  Future<void> _crearProveedor() async {
    Proveedor? p;
    try {
      p = await _svc.crearProveedor(_textoProveedor);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear el proveedor. Revisá la conexión e intentá de nuevo.');
      return;
    }
    if (!mounted) return;
    if (p == null) {
      setState(() => _error = 'El nombre del proveedor debe tener entre 2 y 80 caracteres.');
      return;
    }
    setState(() {
      if (!_proveedores.any((x) => x.id == p!.id)) _proveedores = [..._proveedores, p!];
      _proveedor = p;
      _textoProveedor = p!.nombre;
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
      final real = RecepcionesService.aUnidadItem(_num(_cantReal), _unidad, _item!.unidad);
      if (real != null) _registradas.add((_item!, real));
      if (_otraMas) {
        avisoExito(context, 'Recepción registrada', 'Cargá el siguiente ítem de la factura.');
        setState(_limpiarParaOtro);
        return;
      }
      avisoExito(context, 'Recepción registrada');
      Navigator.pop(context, true);
      return;
    }
    // Si el problema es de un campo, se lo señala con un globo junto a él;
    // si no (sin conexión, permiso), el mensaje va abajo como antes.
    final campo = _svc.campoConError;
    setState(() {
      _guardando = false;
      _error = campo == null ? error : null;
    });
    if (campo != null) avisarCampo(_claves[campo]!, error);
  }

  /// Deja proveedor, factura, fecha y transportador; vacía lo que es de cada ítem.
  void _limpiarParaOtro() {
    _guardando = false;
    _item = null;
    _versionItem++;
    for (final c in [_cantFactura, _cantReal, _lote, _senasac, _precio, _obs]) {
      c.clear();
    }
    _fabricacion = null;
    _vencimiento = null;
    _senasacAuto = false;
    _fotos.clear();
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
                _campo(CampoRecepcion.item, Autocomplete<ItemRecepcion>(
                  key: ValueKey('item$_versionItem'),
                  displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
                  optionsBuilder: (t) => _items.buscar(t.text),
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
                )),
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
                FilaCampos([
                  _campo(CampoRecepcion.factura, _texto(_factura, 'N° de factura', max: 40)),
                  _campo(CampoRecepcion.fecha, _fechaCampo(
                    'Fecha de recepción',
                    _fecha,
                    () => _elegirFecha(
                      actual: _fecha,
                      alElegir: (d) => _fecha = d,
                      hasta: DateTime.now(),
                    ),
                  )),
                ]),
                const SizedBox(height: 16),
                const Text('Cantidades', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                // Layout a medida: la unidad es un desplegable angosto de ancho
                // fijo (o una etiqueta corta), no un campo más — forzarlo a
                // FilaCampos le daría un tercio del ancho por las dudas,
                // dejando menos lugar del que necesitan los otros dos campos.
                LayoutBuilder(builder: (context, constraints) {
                  const anchoUnidad = 78.0;
                  const espacio = 10.0;
                  final anchoCampos = (constraints.maxWidth - anchoUnidad - espacio * 2) / 2;
                  final campoUnidad = _campo(CampoRecepcion.unidad, _unidades.length > 1
                      ? DropdownButtonFormField<String>(
                          initialValue: _unidad,
                          decoration: _deco('Unidad'),
                          items: [
                            for (final u in _unidades) DropdownMenuItem(value: u, child: Text(u)),
                          ],
                          onChanged: (v) => setState(() => _unidad = v ?? _unidad),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(unidadItem,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ));
                  if (anchoCampos >= 130) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _campo(CampoRecepcion.cantidadFactura, _texto(_cantFactura, 'Según factura / etiqueta',
                                numerico: true))),
                        const SizedBox(width: espacio),
                        Expanded(child: _campo(CampoRecepcion.cantidadReal, _texto(_cantReal, 'Real (pesado)', numerico: true))),
                        const SizedBox(width: espacio),
                        SizedBox(width: anchoUnidad, child: campoUnidad),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _campo(CampoRecepcion.cantidadFactura, _texto(_cantFactura, 'Según factura / etiqueta', numerico: true)),
                      const SizedBox(height: espacio),
                      _campo(CampoRecepcion.cantidadReal, _texto(_cantReal, 'Real (pesado)', numerico: true)),
                      const SizedBox(height: espacio),
                      campoUnidad,
                    ],
                  );
                }),
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
                _campo(CampoRecepcion.lote, _texto(_lote, 'N° de lote', max: 40)),
                sep,
                FilaCampos([
                  _campo(CampoRecepcion.fabricacion, _fechaCampo(
                    'Fabricación',
                    _fabricacion,
                    () => _elegirFecha(
                        actual: _fabricacion,
                        alElegir: (d) => _fabricacion = d,
                        hasta: DateTime.now()),
                    borrar: () => setState(() => _fabricacion = null),
                  )),
                  _campo(CampoRecepcion.vencimiento, _fechaCampo(
                    'Vencimiento',
                    _vencimiento,
                    () => _elegirFecha(actual: _vencimiento, alElegir: (d) => _vencimiento = d),
                    borrar: () => setState(() => _vencimiento = null),
                  )),
                ]),
                sep,
                _campo(CampoRecepcion.senasac, _texto(
                  _senasac,
                  'SENASAG (ficha técnica)',
                  max: 40,
                  ayuda: _senasacAuto
                      ? 'Completado solo: ya se conocía para este producto y proveedor.'
                      : 'Si lo escribís una vez, el sistema lo recuerda.',
                  alCambiar: () => _senasacAuto = false,
                )),
                const SizedBox(height: 16),
                const Text('Transporte', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FilaCampos([
                  _campo(CampoRecepcion.transportador, _texto(_transportador, 'Transportador', max: 80)),
                  _campo(CampoRecepcion.precio, _texto(_precio, 'Precio (Bs)', numerico: true)),
                ]),
                const SizedBox(height: 16),
                const Text('Respaldo', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                // Casilleros de foto (factura, etiqueta, la carga…): cada uno con
                // su nombre y la vista previa; el último, vacío, agrega otra.
                _campo(CampoRecepcion.fotos, Wrap(spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < _fotos.length; i++)
                    _CasilleroFoto(
                      etiqueta: 'Foto ${i + 1}',
                      child: Stack(fit: StackFit.expand, children: [
                        Image.memory(_fotos[i].bytes, fit: BoxFit.cover),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () => setState(() => _fotos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  if (_fotos.length < RecepcionesService.maxFotos)
                    _CasilleroFoto(
                      etiqueta: 'Foto ${_fotos.length + 1}',
                      onTap: _elegirFoto,
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined, color: AppColors.primario, size: 28),
                        SizedBox(height: 4),
                        Text('Agregar', style: TextStyle(fontSize: 12, color: AppColors.primario)),
                      ]),
                    ),
                ])),
                sep,
                _campo(CampoRecepcion.observaciones, TextField(
                  controller: _obs,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: _deco('Observaciones (opcional)'),
                )),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _otraMas,
                  onChanged: (v) => setState(() => _otraMas = v ?? false),
                  title: const Text('Después de guardar, cargar otro ítem de esta factura'),
                ),
                if (_registradas.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primario.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Ya registrado de esta factura (${_registradas.length})',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      for (final (item, cant) in _registradas)
                        Text('• ${item.detalle}: ${fmtNum(cant, decimales: 3)} ${item.unidad}',
                            style: const TextStyle(fontSize: 13)),
                      // Pasar lo recibido a un área (todo o una parte): abre el
                      // pedido ya cargado con "Entregar ahora"; el área confirma.
                      if (_almacenId == 'general') ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, [
                            for (final (item, cant) in _registradas) (item.id, cant),
                          ]),
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Entregar a un área'),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
                ],
              ],
            ),
    );
  }
}

/// Un casillero de foto: el nombre arriba ("Foto 1") y la vista previa en un
/// recuadro, o el botón para agregar otra.
class _CasilleroFoto extends StatelessWidget {
  final String etiqueta;
  final Widget child;
  final VoidCallback? onTap;
  const _CasilleroFoto({required this.etiqueta, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 104,
              height: 104,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: onTap == null ? null : AppColors.primario.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: onTap == null ? const Color(0xFFD5DADF) : AppColors.primario.withValues(alpha: 0.6)),
              ),
              child: child,
            ),
          ),
        ],
      );
}
