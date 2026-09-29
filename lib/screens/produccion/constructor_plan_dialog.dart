import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/formatters.dart';
import '../../utils/notificaciones.dart';
import '../../utils/responsive.dart';

/// Una fila de la tabla que se está armando: el producto elegido más la
/// cantidad tal como la escribe el ingeniero (paquetes/cajas O botellas
/// sueltas, según tenga definida esa relación el producto) — igual que la
/// planilla que ya manejan en papel/Excel.
///
/// "Total botellas" y "Total litros" se calculan solos a partir de la
/// cantidad, pero quedan editables: si alguien los toca a mano (para
/// corregir un dato real distinto del calculado), ese valor manual queda
/// fijo y ya no se pisa solo con la cantidad — hasta que se cambie el
/// producto, que sí fuerza a recalcular.
class _FilaPlan {
  ProductoTerminado producto;
  final TextEditingController cantidadCtrl = TextEditingController();
  final TextEditingController totalBotellasCtrl = TextEditingController();
  final TextEditingController totalLitrosCtrl = TextEditingController();
  bool totalesManuales = false;

  _FilaPlan(this.producto);

  bool get usaPaquetes => producto.botellasPorPaquete != null;
  double get cantidad => double.tryParse(cantidadCtrl.text) ?? 0;
  double get _totalBotellasCalculado =>
      usaPaquetes ? cantidad * producto.botellasPorPaquete! : cantidad;
  double get _totalLitrosCalculado => _totalBotellasCalculado * producto.litrosPorBotella;

  double get totalBotellas => double.tryParse(totalBotellasCtrl.text) ?? 0;
  double get totalLitros => double.tryParse(totalLitrosCtrl.text) ?? 0;

  void recalcular({bool forzar = false}) {
    if (totalesManuales && !forzar) return;
    if (forzar) totalesManuales = false;
    totalBotellasCtrl.text = _totalBotellasCalculado.toStringAsFixed(0);
    totalLitrosCtrl.text = _totalLitrosCalculado.toStringAsFixed(2);
  }

  void dispose() {
    cantidadCtrl.dispose();
    totalBotellasCtrl.dispose();
    totalLitrosCtrl.dispose();
  }
}

/// Arma el plan de producción del día como una tabla editable: se van
/// agregando productos con su cantidad, se puede corregir o eliminar
/// cualquier línea antes de confirmar, y recién al tocar "Guardar plan"
/// esas líneas pasan a la lista de tareas del día (una por una, con
/// [ProduccionService.agregarProductoAlPlan]) — así el ingeniero arma todo
/// el plan de una vez, en vez de un producto por vez.
class ConstructorPlanDialog extends StatefulWidget {
  final String planId;
  final List<ProductoTerminado> productos;
  const ConstructorPlanDialog(
      {super.key, required this.planId, required this.productos});

  @override
  State<ConstructorPlanDialog> createState() => _ConstructorPlanDialogState();
}

class _ConstructorPlanDialogState extends State<ConstructorPlanDialog> {
  static const _colN = 28.0;
  static const _colProducto = 170.0;
  static const _colPaquetes = 100.0;
  static const _colBotellas = 80.0;
  static const _colTotalBotellas = 90.0;
  static const _colTotalLitros = 90.0;
  static const _colEliminar = 60.0;
  static const _anchoTabla = _colN +
      _colProducto +
      _colPaquetes +
      _colBotellas +
      _colTotalBotellas +
      _colTotalLitros +
      _colEliminar;

  final List<_FilaPlan> _filas = [];
  bool _guardando = false;

  Widget _celdaEditable(TextEditingController ctrl, {VoidCallback? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4)),
        onChanged: (_) => setState(() => onChanged?.call()),
      ),
    );
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _agregarFila() async {
    ProductoTerminado? producto;
    final cantidadCtrl = TextEditingController();

    final elegido = await showDialog<ProductoTerminado>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Agregar producto'),
            content: SizedBox(
              width: anchoDialogo(ctx, 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Autocomplete<ProductoTerminado>(
                    displayStringForOption: (p) => p.nombre,
                    optionsBuilder: (v) {
                      final q = v.text.trim().toLowerCase();
                      if (q.isEmpty) return widget.productos;
                      return widget.productos
                          .where((p) => p.nombre.toLowerCase().contains(q));
                    },
                    onSelected: (p) => setLocal(() => producto = p),
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (_) => setLocal(() => producto = null),
                        decoration: const InputDecoration(
                          labelText: 'Producto *',
                          hintText: 'Buscar por nombre...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      );
                    },
                  ),
                  if (producto != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: cantidadCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: producto!.botellasPorPaquete != null
                            ? 'Paquetes/Cajas '
                                '(${fmtNum(producto!.botellasPorPaquete, decimales: 0)} botellas c/u)'
                            : 'Botellas',
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: producto != null && cantidadCtrl.text.isNotEmpty
                      ? () => Navigator.pop(ctx, producto)
                      : null,
                  child: const Text('Agregar a la tabla')),
            ],
          );
        },
      ),
    );

    if (elegido != null) {
      final fila = _FilaPlan(elegido)..cantidadCtrl.text = cantidadCtrl.text;
      fila.recalcular();
      setState(() => _filas.add(fila));
    }
  }

  void _eliminarFila(int i) {
    setState(() => _filas.removeAt(i).dispose());
  }

  /// Permite cambiar el producto de una línea ya agregada (tocando la
  /// celda "Producto"), sin tener que eliminarla y volver a cargarla.
  Future<void> _editarProducto(int i) async {
    final elegido = await showDialog<ProductoTerminado>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar producto'),
        content: SizedBox(
          width: anchoDialogo(ctx, 380),
          child: Autocomplete<ProductoTerminado>(
            displayStringForOption: (p) => p.nombre,
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              if (q.isEmpty) return widget.productos;
              return widget.productos
                  .where((p) => p.nombre.toLowerCase().contains(q));
            },
            onSelected: (p) => Navigator.pop(ctx, p),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Producto *',
                  hintText: 'Buscar por nombre...',
                  prefixIcon: Icon(Icons.search),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      ),
    );
    if (elegido != null) {
      setState(() {
        _filas[i].producto = elegido;
        _filas[i].recalcular(forzar: true);
      });
    }
  }

  Future<void> _guardarPlan() async {
    setState(() => _guardando = true);
    final usuario = context.read<AuthService>().usuarioActual!;
    for (final f in _filas) {
      if (f.totalLitros <= 0) continue;
      await ProduccionService.agregarProductoAlPlan(
        planId: widget.planId,
        producto: f.producto,
        litros: f.totalLitros,
        usuarioId: usuario.id,
      );
    }
    if (mounted) {
      mostrarExito(context, 'Plan guardado.');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    return AlertDialog(
      title: const Text('Armar plan de producción'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Fecha: ${fmtFecha(DateTime.now())}',
                      style: const TextStyle(color: Colors.black54)),
                ),
                OutlinedButton.icon(
                  onPressed: _agregarFila,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar producto'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal + vertical: la tabla tiene demasiadas columnas para
            // achicarla en una pantalla angosta sin volverla ilegible, así
            // que en mobile se desplaza en vez de comprimirse. El ancho del
            // SizedBox es EXACTAMENTE la suma de los anchos de columna (sin
            // padding extra en los Container de abajo) para que nunca se
            // desborde.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _anchoTabla,
                child: Column(
                  children: [
                    Container(
                      color: AppColors.primario,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const Row(
                        children: [
                          _Celda('N°', ancho: _colN, encabezado: true),
                          _Celda('Producto', ancho: _colProducto, encabezado: true),
                          _Celda('Paquetes/Cajas',
                              ancho: _colPaquetes, encabezado: true),
                          _Celda('Botellas', ancho: _colBotellas, encabezado: true),
                          _Celda('Total botellas',
                              ancho: _colTotalBotellas, encabezado: true),
                          _Celda('Total litros',
                              ancho: _colTotalLitros, encabezado: true),
                          _Celda('Eliminar', ancho: _colEliminar, encabezado: true),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: _filas.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                  'Todavía no agregaste ningún producto.',
                                  style: TextStyle(color: Colors.black54)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filas.length,
                              itemBuilder: (context, i) {
                                final f = _filas[i];
                                return Container(
                                  decoration: BoxDecoration(
                                    color: i.isEven
                                        ? Colors.white
                                        : const Color(0xFFF4F6F8),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade300)),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      _Celda('${i + 1}', ancho: _colN),
                                      SizedBox(
                                        width: _colProducto,
                                        child: InkWell(
                                          onTap: () => _editarProducto(i),
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4),
                                            child: Text(
                                              f.producto.nombre,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  decoration:
                                                      TextDecoration.underline,
                                                  decorationStyle:
                                                      TextDecorationStyle.dotted),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _colPaquetes,
                                        child: f.usaPaquetes
                                            ? _celdaEditable(f.cantidadCtrl,
                                                onChanged: f.recalcular)
                                            : const _Celda('0', ancho: _colPaquetes),
                                      ),
                                      SizedBox(
                                        width: _colBotellas,
                                        child: !f.usaPaquetes
                                            ? _celdaEditable(f.cantidadCtrl,
                                                onChanged: f.recalcular)
                                            : const _Celda('0', ancho: _colBotellas),
                                      ),
                                      SizedBox(
                                        width: _colTotalBotellas,
                                        child: _celdaEditable(f.totalBotellasCtrl,
                                            onChanged: () => f.totalesManuales = true),
                                      ),
                                      SizedBox(
                                        width: _colTotalLitros,
                                        child: _celdaEditable(f.totalLitrosCtrl,
                                            onChanged: () => f.totalesManuales = true),
                                      ),
                                      SizedBox(
                                        width: _colEliminar,
                                        child: IconButton(
                                          icon: const Icon(Icons.close,
                                              size: 18, color: Colors.red),
                                          onPressed: () => _eliminarFila(i),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Tocá "Producto" para cambiarlo, o cualquier cantidad para '
                  'corregirla. "Total botellas" y "Total litros" se calculan '
                  'solos, pero también se pueden editar a mano si el dato '
                  'real es otro.',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primario,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Usuario: ${usuario.nombreCompleto}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                  Text('Perfil: ${Rol.etiqueta(usuario.rol)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: (_filas.isEmpty || _guardando) ? null : _guardarPlan,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar plan'),
        ),
      ],
    );
  }
}

class _Celda extends StatelessWidget {
  final String texto;
  final double ancho;
  final bool encabezado;
  const _Celda(this.texto, {required this.ancho, this.encabezado = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          texto,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: encabezado ? FontWeight.bold : FontWeight.normal,
            color: encabezado ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
