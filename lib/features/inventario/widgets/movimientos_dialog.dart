import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/existencia_item.dart';
import '../models/movimiento_inv.dart';
import '../services/inventario_service.dart';

/// Historial de movimientos de un ítem y alta de ingresos / salidas manuales
/// (saldo inicial, consumo, rotura…). Un movimiento manual no se edita ni se
/// borra: se REVIERTE, y el original queda a la vista. Solo UI; las reglas
/// las tiene el service y, al final, el servidor.
class MovimientosDialog extends StatefulWidget {
  final InventarioService servicio;
  final ExistenciaItem item;
  const MovimientosDialog({super.key, required this.servicio, required this.item});

  @override
  State<MovimientosDialog> createState() => _MovimientosDialogState();
}

class _MovimientosDialogState extends State<MovimientosDialog> {
  final _cantidad = TextEditingController();
  final _motivo = TextEditingController();
  List<MovimientoInv> _movs = [];
  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;
  String? _error;
  String? _modo; // 'entrada' | 'salida' | null

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _motivo.dispose();
    super.dispose();
  }

  /// El ítem con el stock al día (el service recarga después de cada cambio).
  ExistenciaItem get _item => widget.servicio.existencias.firstWhere(
        (e) => e.itemId == widget.item.itemId && e.almacenId == widget.item.almacenId,
        orElse: () => widget.item,
      );

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final movs = await widget.servicio.movimientosDe(widget.item);
      if (!mounted) return;
      setState(() {
        _movs = movs;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _errorCarga = 'No se pudo cargar el historial. Revisá la conexión o que la '
            'migración v30 esté ejecutada.';
      });
    }
  }

  void _abrir(String modo) => setState(() {
        _modo = _modo == modo ? null : modo;
        _error = null;
      });

  Future<void> _registrar() async {
    final valor = double.tryParse(_cantidad.text.trim().replaceAll(',', '.'));
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio
        .registrarMovimiento(_item, tipo: _modo!, cantidad: valor, motivo: _motivo.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _guardando = false;
        _error = error;
      });
      return;
    }
    mostrarExito(context, _modo == 'entrada' ? 'Ingreso registrado.' : 'Salida registrada.');
    _cantidad.clear();
    _motivo.clear();
    setState(() {
      _guardando = false;
      _modo = null;
    });
    await _cargar();
  }

  Future<void> _revertir(MovimientoInv mov) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _MotivoReversion(mov: mov, unidad: _item.unidad),
    );
    if (motivo == null || !mounted) return;
    final error = await widget.servicio.revertirMovimiento(mov, motivo);
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Movimiento revertido.');
    } else {
      mostrarError(context, error);
    }
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final pantalla = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (pantalla.width - 32).clamp(320.0, 900.0),
          maxHeight: pantalla.height * 0.92,
        ),
        child: ListenableBuilder(
          listenable: widget.servicio,
          builder: (context, _) {
            final item = _item;
            final puede = widget.servicio.puedeEditar;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    height: 4,
                    decoration: const BoxDecoration(gradient: AppColors.gradientePrincipal)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
                  child: Row(children: [
                    const Icon(Icons.swap_vert, color: AppColors.primario, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.detalle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          Text(
                              '${item.codigo} · Stock: ${fmtNum(item.cantidadSistema)} ${item.unidad}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black38),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                ),
                if (puede)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Wrap(spacing: 8, runSpacing: 6, children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                _modo == 'entrada' ? AppColors.primario : Colors.black87),
                        onPressed: () => _abrir('entrada'),
                        icon: const Icon(Icons.add),
                        label: const Text('Ingreso'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                _modo == 'salida' ? const Color(0xFFDC2626) : Colors.black87),
                        onPressed: () => _abrir('salida'),
                        icon: const Icon(Icons.remove),
                        label: const Text('Salida'),
                      ),
                    ]),
                  ),
                if (_modo != null) _formulario(item),
                const Divider(height: 1),
                Flexible(child: _historial(item, puede)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _formulario(ExistenciaItem item) {
    final esEntrada = _modo == 'entrada';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              esEntrada
                  ? 'Ingreso manual (saldo inicial, devolución, hallazgo…). '
                      'Para mercadería con factura usá Recepciones.'
                  : 'Salida manual (consumo, rotura, préstamo…). '
                      'Sale primero lo que vence antes.',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: _cantidad,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad (${item.unidad})',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _motivo,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: esEntrada ? AppColors.primario : const Color(0xFFDC2626)),
              onPressed: _guardando ? null : _registrar,
              child: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(esEntrada ? 'Registrar ingreso' : 'Registrar salida'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historial(ExistenciaItem item, bool puede) {
    if (_cargando) {
      return const Padding(
          padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    if (_errorCarga != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_errorCarga!, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_movs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('Este ítem todavía no tiene movimientos.',
                style: TextStyle(color: Colors.black54))),
      );
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columnSpacing: 20,
          columns: [
            const DataColumn(label: Text('Fecha')),
            const DataColumn(label: Text('Tipo')),
            const DataColumn(label: Text('Cantidad'), numeric: true),
            const DataColumn(label: Text('Origen')),
            const DataColumn(label: Text('Motivo')),
            const DataColumn(label: Text('Usuario')),
            if (puede) const DataColumn(label: Text('')),
          ],
          rows: [for (final m in _movs) _fila(m, item, puede)],
        ),
      ),
    );
  }

  DataRow _fila(MovimientoInv m, ExistenciaItem item, bool puede) {
    final entra = m.cantidad > 0;
    final color = m.tipo == 'ajuste'
        ? const Color(0xFFD97706)
        : (entra ? AppColors.primario : const Color(0xFFDC2626));
    final etiqueta = m.tipo == 'ajuste' ? 'Ajuste' : (entra ? 'Ingreso' : 'Salida');
    final origen = [
      m.origen,
      if (m.nLote != null && m.nLote!.isNotEmpty) 'lote ${m.nLote}',
    ].join(' · ');
    final tachado = m.revertido ? const TextStyle(decoration: TextDecoration.lineThrough) : null;

    return DataRow(cells: [
      DataCell(Text(fmtFechaHora(m.fecha), style: tachado)),
      DataCell(Text(etiqueta, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
      DataCell(Text(
          '${entra ? '+' : ''}${fmtNum(m.cantidad)} ${item.unidad}',
          style: TextStyle(fontWeight: FontWeight.w600, color: color)
              .merge(tachado))),
      DataCell(Text(m.revertido ? '$origen (revertido)' : origen)),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Tooltip(
            message: m.motivo ?? '',
            child: Text(m.motivo ?? '—', overflow: TextOverflow.ellipsis, maxLines: 2)),
      )),
      DataCell(Text(m.usuarioNombre ?? '—')),
      if (puede)
        DataCell(m.sePuedeRevertir
            ? TextButton(onPressed: () => _revertir(m), child: const Text('Revertir'))
            : const SizedBox.shrink()),
    ]);
  }
}

/// Pide el motivo para revertir un movimiento.
class _MotivoReversion extends StatefulWidget {
  final MovimientoInv mov;
  final String unidad;
  const _MotivoReversion({required this.mov, required this.unidad});

  @override
  State<_MotivoReversion> createState() => _MotivoReversionState();
}

class _MotivoReversionState extends State<_MotivoReversion> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mov;
    return AlertDialog(
      title: const Text('Revertir movimiento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${m.cantidad > 0 ? 'Ingreso' : 'Salida'} de '
              '${fmtNum(m.cantidad.abs())} ${widget.unidad} del ${fmtFechaHora(m.fecha)}. '
              'Se registra el movimiento contrario; el original queda en el historial.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Revertir')),
      ],
    );
  }
}
