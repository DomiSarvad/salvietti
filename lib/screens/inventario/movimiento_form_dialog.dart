import 'package:flutter/material.dart';
import '../../shared/alertas.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../utils/formatters.dart';
import '../../utils/notificaciones.dart';
import '../../widgets/autocompletar_texto.dart';
import '../../widgets/formulario_widgets.dart';

/// Registrar entrada/salida/ajuste, siguiendo la estructura acordada del
/// wireframe (pantallas 1f "Ingreso" y 1h "Salida rápida"): se busca el
/// insumo por código o nombre y el resto de los datos que ya conoce el
/// sistema (detalle, unidad, proveedor habitual, responsable) se
/// autocompletan solos como campos propios — siguen siendo editables,
/// pero no hay que volver a escribirlos.
///
/// El buscador de insumo es solo para ENCONTRAR un ítem ya existente
/// (no se puede crear uno nuevo desde acá, a propósito: mezclar "buscar"
/// con "crear" en el mismo campo es lo que hace fácil equivocarse de
/// ítem sin darse cuenta). Para dar de alta un insumo nuevo se usa el
/// botón "Nuevo ítem" de la pantalla de Inventario. La lista de opciones
/// que recibe este diálogo (`widget.items`) ya viene filtrada a la
/// categoría activa (Tapas/Preformas/Materia Prima), así que el
/// autocompletar de código siempre busca dentro del tipo de inventario
/// que se está registrando.
class MovimientoFormDialog extends StatefulWidget {
  final List<Insumo> items;
  final String tabla;
  final String usuarioId;
  const MovimientoFormDialog(
      {super.key,
      required this.items,
      required this.tabla,
      required this.usuarioId});

  @override
  State<MovimientoFormDialog> createState() => _MovimientoFormDialogState();
}

class _MovimientoFormDialogState extends State<MovimientoFormDialog> {
  Insumo? _seleccionado;
  String _tipo = 'ingreso';
  final _cantidadCtrl = TextEditingController();
  final _loteCtrl = TextEditingController();
  final _facturaCtrl = TextEditingController();
  String _proveedor = '';
  final _observacionCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  DateTime? _vencimiento;
  bool _guardando = false;
  List<String> _proveedores = [];

  @override
  void initState() {
    super.initState();
    InventarioService.listarProveedores().then((lista) {
      if (mounted) setState(() => _proveedores = lista);
    });
    // Recalcula la vista previa de stock en cada tecla de "Cantidad".
    _cantidadCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _loteCtrl.dispose();
    _facturaCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_seleccionado == null || _cantidadCtrl.text.isEmpty) return;
    setState(() => _guardando = true);

    final mov = Movimiento(
      tablaOrigen: _seleccionado!.tabla,
      itemId: _seleccionado!.id,
      tipo: _tipo,
      cantidad: double.tryParse(_cantidadCtrl.text) ?? 0,
      unidadMedida: _seleccionado!.unidadMedida,
      lote: _loteCtrl.text.isEmpty ? null : _loteCtrl.text,
      fechaVencimiento: _vencimiento,
      proveedor: _proveedor.trim().isEmpty ? null : _proveedor.trim(),
      nFactura: _facturaCtrl.text.isEmpty ? null : _facturaCtrl.text,
      observacion:
          _observacionCtrl.text.isEmpty ? null : _observacionCtrl.text,
      usuarioId: widget.usuarioId,
      creadoEn: _fecha,
    );

    final enviadoDirecto = await InventarioService.registrarMovimiento(mov);
    if (mounted) {
      if (enviadoDirecto) {
        avisoExito(context, 'Registro guardado');
      } else {
        mostrarInfo(context,
            'Sin conexión: guardado localmente. Se sincronizará automáticamente.');
      }
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;
    final s = _seleccionado;
    final cantidad = double.tryParse(_cantidadCtrl.text);

    return ModalFormulario(
      titulo: 'Registrar movimiento',
      icono: Icons.swap_vert,
      textoBoton: 'Registrar',
      guardando: _guardando,
      onGuardar:
          (s == null || _cantidadCtrl.text.isEmpty) ? null : _guardar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SeccionFormulario('Movimiento de inventario'),
          CampoFormulario(
            etiqueta: 'Código de insumo *',
            child: Autocomplete<Insumo>(
              displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
              optionsBuilder: (textEditingValue) {
                final q = textEditingValue.text.trim().toLowerCase();
                if (q.isEmpty) return widget.items;
                return widget.items.where((i) =>
                    i.detalle.toLowerCase().contains(q) ||
                    i.codigo.toLowerCase().contains(q));
              },
              onSelected: (i) => setState(() {
                _seleccionado = i;
                // Autocompleta con el dato ya conocido del insumo, pero
                // sigue siendo un campo editable por si corresponde otro
                // proveedor puntual para esta entrada.
                if (_tipo == 'ingreso' &&
                    i.proveedorHabitual != null &&
                    i.proveedorHabitual!.isNotEmpty) {
                  _proveedor = i.proveedorHabitual!;
                }
              }),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (_) => setState(() => _seleccionado = null),
                  decoration: decoracionFormulario(
                      hint: 'Buscar por código o nombre...',
                      sufijo: const Icon(Icons.search)),
                );
              },
            ),
          ),
          if (s == null)
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Elegí un ítem de la lista de resultados (si no existe, '
                'creálo primero desde "Nuevo ítem" en Inventario).',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          // Detalle y Unidad se autocompletan solos apenas se elige el
          // código — quedan de solo lectura (editar el nombre del insumo es
          // trabajo de "Editar ítem" en Inventario).
          CampoFormulario(
              etiqueta: 'Detalle', child: ValorFormulario(s?.detalle ?? '—')),
          CampoFormulario(
            etiqueta: 'Tipo de movimiento',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ingreso', label: Text('Entrada')),
                    ButtonSegment(value: 'salida', label: Text('Salida')),
                    ButtonSegment(value: 'ajuste', label: Text('Ajuste')),
                  ],
                  selected: {_tipo},
                  onSelectionChanged: (sel) => setState(() => _tipo = sel.first),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: CampoFormulario(
                  etiqueta: 'Cantidad *',
                  child: TextField(
                    controller: _cantidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: decoracionFormulario(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CampoFormulario(
                    etiqueta: 'Unidad',
                    child: ValorFormulario(s?.unidadMedida ?? '—')),
              ),
            ],
          ),
          CampoFormulario(
            etiqueta: 'Lote',
            child: TextField(
                controller: _loteCtrl, decoration: decoracionFormulario()),
          ),
          CampoFormulario(
            etiqueta: 'Fecha',
            child: ValorFormulario(
              fmtFecha(_fecha),
              icono: Icons.calendar_today,
              onTap: () async {
                final f = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                  lastDate: DateTime.now(),
                );
                if (f != null) {
                  setState(() => _fecha = DateTime(
                      f.year, f.month, f.day, _fecha.hour, _fecha.minute));
                }
              },
            ),
          ),
          CampoFormulario(
            etiqueta: 'Fecha de vencimiento (opcional)',
            child: ValorFormulario(
              _vencimiento == null ? 'dd/mm/aaaa' : fmtFecha(_vencimiento),
              icono: Icons.calendar_today,
              onTap: () async {
                final f = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (f != null) setState(() => _vencimiento = f);
              },
            ),
          ),
          if (_tipo == 'ingreso') ...[
            CampoFormulario(
              etiqueta: 'Proveedor',
              child: AutocompletarTexto(
                // Al cambiar de insumo, se recrea con el proveedor
                // habitual como valor inicial (sigue siendo editable).
                key: ValueKey('proveedor-${s?.id}'),
                label: 'Proveedor',
                valorInicial: _proveedor,
                opciones: _proveedores,
                onChanged: (v) => _proveedor = v,
                decoracion: decoracionFormulario(),
              ),
            ),
            CampoFormulario(
              etiqueta: 'N° factura / remisión',
              child: TextField(
                  controller: _facturaCtrl, decoration: decoracionFormulario()),
            ),
          ],
          CampoFormulario(
              etiqueta: 'Responsable',
              child: ValorFormulario(usuario.nombreCompleto)),
          CampoFormulario(
            etiqueta: 'Observación',
            child: TextField(
              controller: _observacionCtrl,
              maxLines: 2,
              decoration: decoracionFormulario(),
            ),
          ),
          if (s != null && cantidad != null && cantidad > 0) ...[
            const SizedBox(height: 8),
            _vistaPreviaStock(s, cantidad),
          ],
        ],
      ),
    );
  }

  /// Simulación en vivo de cómo queda el stock, igual que el recuadro
  /// punteado de los wireframes de Ingreso/Salida — ayuda a detectar un
  /// error de tipeo antes de guardar.
  Widget _vistaPreviaStock(Insumo s, double cantidad) {
    final signo = _tipo == 'salida' ? -1 : 1; // ajuste se aplica tal cual
    final despues = s.cantidadReal + signo * cantidad;
    final consumo = s.consumoPromedioDia;
    final diasAntes = consumo > 0 ? s.cantidadReal / consumo : 999.0;
    final diasDespues = consumo > 0 ? despues / consumo : 999.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Stock ${_tipo == 'ajuste' ? 'con el ajuste' : 'después'}: '
        '${fmtNum(s.cantidadReal, decimales: 0)} → ${fmtNum(despues, decimales: 0)} ${s.unidadMedida}'
        '${consumo > 0 ? ' · días de existencia: ${fmtNum(diasAntes, decimales: 1)} → ${fmtNum(diasDespues, decimales: 1)}' : ''}',
        style: const TextStyle(fontSize: 12.5, color: AppColors.primario),
      ),
    );
  }
}
