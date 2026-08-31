import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import 'editar_consumo_dialog.dart';
import 'produccion_captura_dialog.dart';
import 'productos_catalogo_dialog.dart';

/// "Lo que el ingeniero organizó para el día": el Jefe de Producción
/// agrega cada producto terminado (sabor + tamaño + envase) con sus
/// litros planificados; al terminar de producirlo lo marca (como una
/// lista de tareas) indicando botellas producidas y merma, y el sistema
/// descuenta automáticamente materia prima, preformas y tapas (trigger
/// en BD). Es el único rol que edita este plan.
class ProduccionPlannerScreen extends StatefulWidget {
  const ProduccionPlannerScreen({super.key});
  @override
  State<ProduccionPlannerScreen> createState() =>
      _ProduccionPlannerScreenState();
}

class _ProduccionPlannerScreenState extends State<ProduccionPlannerScreen> {
  PlanProduccion? _plan;
  List<ProductoTerminado> _productos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final usuario = context.read<AuthService>().usuarioActual!;
    PlanProduccion? plan;
    try {
      plan = await ProduccionService.planDeHoy(usuario.id);
    } catch (_) {
      plan = null; // sin conexión: no se puede planificar hasta reconectar
    }
    final productos = await ProduccionService.listarProductosTerminados();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _productos = productos;
      _cargando = false;
    });
  }

  /// El Jefe de Producción elige el PRODUCTO (buscador, igual que con los
  /// insumos) y cuántos PAQUETES/CAJAS van a salir — litros y botellas se
  /// calculan solos a partir de la ficha del producto, tal como en el
  /// reporte que ya manejan. Si el producto no tiene definida la cantidad
  /// de botellas por paquete, se puede cargar la cantidad de botellas
  /// directamente.
  Future<void> _agregarProducto() async {
    ProductoTerminado? producto;
    final paquetesCtrl = TextEditingController();
    final botellasCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final porPaquete = producto?.botellasPorPaquete;
          double? botellas;
          if (producto != null) {
            botellas = porPaquete != null
                ? (double.tryParse(paquetesCtrl.text) ?? 0) * porPaquete
                : double.tryParse(botellasCtrl.text);
          }
          final litros =
              (producto != null && botellas != null && botellas > 0)
                  ? botellas * producto!.litrosPorBotella
                  : null;

          return AlertDialog(
            title: const Text('Agregar producto al plan del día'),
            content: SizedBox(
              width: anchoDialogo(ctx, 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_productos.isEmpty)
                    const Text('Primero cargá al menos un producto desde '
                        '"Productos".')
                  else
                    Autocomplete<ProductoTerminado>(
                      displayStringForOption: (p) => p.nombre,
                      optionsBuilder: (v) {
                        final q = v.text.trim().toLowerCase();
                        if (q.isEmpty) return _productos;
                        return _productos
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
                    if (porPaquete != null)
                      TextField(
                        controller: paquetesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: 'Paquetes/Cajas '
                                '(${fmtNum(porPaquete, decimales: 0)} botellas c/u)'),
                        onChanged: (_) => setLocal(() {}),
                      )
                    else
                      TextField(
                        controller: botellasCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Botellas'),
                        onChanged: (_) => setLocal(() {}),
                      ),
                    const SizedBox(height: 8),
                    Text(
                        litros != null
                            ? '= ${fmtNum(botellas, decimales: 0)} botellas · '
                                '${fmtNum(litros, decimales: 0)} litros a producir'
                            : 'Ingresá la cantidad para calcular litros y botellas.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: (litros != null && litros > 0)
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  child: const Text('Agregar')),
            ],
          );
        },
      ),
    );

    if (ok == true && producto != null) {
      final porPaquete = producto!.botellasPorPaquete;
      final botellas = porPaquete != null
          ? (double.tryParse(paquetesCtrl.text) ?? 0) * porPaquete
          : double.tryParse(botellasCtrl.text) ?? 0;
      final litros = botellas * producto!.litrosPorBotella;
      final usuario = context.read<AuthService>().usuarioActual!;
      await ProduccionService.agregarProductoAlPlan(
        planId: _plan!.id,
        producto: producto!,
        litros: litros,
        usuarioId: usuario.id,
      );
      _cargar();
    }
  }

  Future<void> _marcarCompletado(PlanProduccionDetalle d) async {
    final usuario = context.read<AuthService>().usuarioActual!;
    final estimado = d.litrosPorBotella != null && d.litrosPorBotella! > 0
        ? (d.litrosPlanificados / d.litrosPorBotella!).round()
        : null;
    final botellasCtrl =
        TextEditingController(text: estimado?.toString() ?? '');
    final mermaCtrl = TextEditingController(text: '0');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Marcar como completado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Se descontará automáticamente la materia prima de "${d.sabor}"'
                '${d.nombreProducto != null ? ', además de la preforma y tapa de "${d.nombreProducto}"' : ''}. '
                'Esta acción no se puede deshacer.'),
            const SizedBox(height: 12),
            TextField(
              controller: botellasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Botellas producidas'),
            ),
            TextField(
              controller: mermaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Merma (litros)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar == true) {
      final botellas = double.tryParse(botellasCtrl.text) ?? 0;
      final merma = double.tryParse(mermaCtrl.text) ?? 0;
      final litrosProducidos = d.litrosPorBotella != null
          ? botellas * d.litrosPorBotella!
          : null;
      await ProduccionService.marcarComoCompletado(
        detalleId: d.id,
        usuarioId: usuario.id,
        botellasProducidas: botellas,
        mermaLitros: merma,
        litrosProducidos: litrosProducidos,
      );
      _cargar();
    }
  }

  Future<void> _abrirCatalogo() async {
    await showDialog(context: context, builder: (_) => const ProductosCatalogoDialog());
    _cargar();
  }

  Future<void> _abrirEditarConsumo() async {
    await showDialog(context: context, builder: (_) => const EditarConsumoDialog());
  }

  Future<void> _guardarImagen() async {
    if (_plan == null) return;
    await showDialog(
      context: context,
      builder: (_) => ProduccionCapturaDialog(plan: _plan!),
    );
  }

  void _copiarResumen() {
    final plan = _plan;
    if (plan == null || plan.detalle.isEmpty) return;
    final buffer = StringBuffer('Producción de hoy — ${fmtFecha(plan.fecha)}\n\n');
    for (final d in plan.detalle) {
      final nombre = d.nombreProducto ?? d.sabor;
      if (d.completado) {
        buffer.writeln('✔ $nombre — ${fmtNum(d.litrosProducidos, decimales: 0)} L'
            '${d.botellasProducidas != null ? ' (${fmtNum(d.botellasProducidas, decimales: 0)} botellas)' : ''}'
            '${d.mermaLitros > 0 ? ' — merma: ${fmtNum(d.mermaLitros, decimales: 0)} L' : ''}');
      } else {
        buffer.writeln('• $nombre — ${fmtNum(d.litrosPlanificados, decimales: 0)} L planificados');
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Resumen copiado. Pégalo donde quieras compartirlo.')));
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    if (_cargando) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Producción del día',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Wrap en vez de Row: con varios botones, en una ventana angosta
          // un Row fijo se desborda; acá simplemente pasan a la siguiente
          // línea.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _plan == null || _plan!.detalle.isEmpty
                    ? null
                    : _guardarImagen,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartir'),
              ),
              OutlinedButton.icon(
                onPressed: _copiarResumen,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copiar resumen'),
              ),
              if (usuario.puedeEditarProduccion) ...[
                OutlinedButton.icon(
                  onPressed: _abrirCatalogo,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Productos'),
                ),
                OutlinedButton.icon(
                  onPressed: _abrirEditarConsumo,
                  icon: const Icon(Icons.tune),
                  label: const Text('Editar consumo'),
                ),
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: _agregarProducto,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar producto'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Marca cada producto cuando termine de embotellarse: el sistema '
              'descuenta automáticamente materia prima, preformas y tapas '
              'según la receta y las botellas producidas.',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Expanded(
            child: _plan == null || _plan!.detalle.isEmpty
                ? const Center(child: Text('Aún no hay productos planificados hoy.'))
                : ListView(
                    children: _plan!.detalle
                        .map((d) => Card(
                              child: ListTile(
                                leading: Icon(
                                  d.completado
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: d.completado
                                      ? Colors.green
                                      : Colors.grey,
                                  size: 32,
                                ),
                                title: Text(d.nombreProducto ?? d.sabor,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(d.completado
                                    ? '${fmtNum(d.botellasProducidas, decimales: 0)} botellas producidas'
                                        '${d.mermaLitros > 0 ? ' · merma: ${fmtNum(d.mermaLitros, decimales: 0)} L' : ''}'
                                    : '${d.litrosPlanificados.toStringAsFixed(0)} litros planificados'),
                                trailing: d.completado
                                    ? const Chip(label: Text('Completado'))
                                    : (usuario.puedeEditarProduccion
                                        ? ElevatedButton(
                                            onPressed: () => _marcarCompletado(d),
                                            child: const Text('Marcar hecho'),
                                          )
                                        : const Text('Pendiente',
                                            style: TextStyle(color: Colors.grey))),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
