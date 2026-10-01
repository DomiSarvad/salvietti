import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/produccion_service.dart';
import '../../shared/ayuda/tour_ayuda.dart';
import '../../utils/formatters.dart';
import 'constructor_plan_dialog.dart';
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
  /// Al tocar un producto de la lista, si esto está definido, se navega a
  /// Jarabes con ese sabor listo para calcular el preparado (en vez de
  /// tener que ir a Jarabes y buscarlo de nuevo ahí).
  final void Function(String sabor)? onIrAJarabes;
  const ProduccionPlannerScreen({super.key, this.onIrAJarabes});
  @override
  State<ProduccionPlannerScreen> createState() =>
      _ProduccionPlannerScreenState();
}

class _ProduccionPlannerScreenState extends State<ProduccionPlannerScreen> {
  PlanProduccion? _plan;
  List<ProductoTerminado> _productos = [];
  bool _cargando = true;

  final _pasoArmarPlan = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Armar plan',
    texto: 'El Jefe de Producción arma acá la tabla del día: qué productos y cuántos '
        'litros planificados. Al guardar, pasan a la lista de tareas de abajo.',
  );
  final _pasoLista = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Marcar como completado',
    texto: 'Tocá "Marcar hecho" cuando termine de embotellarse un producto: el sistema '
        'descuenta automáticamente materia prima, preformas y tapas según la receta y '
        'las botellas producidas.',
  );

  @override
  void initState() {
    super.initState();
    _cargar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context,
            idTour: 'produccion_del_dia', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoArmarPlan, _pasoLista];

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

  /// Abre la tabla donde el Jefe de Producción arma el plan del día:
  /// agrega productos, corrige o elimina líneas, y solo al confirmar
  /// "Guardar plan" esas líneas pasan a la lista de tareas de abajo.
  Future<void> _armarPlan() async {
    if (_plan == null) return;
    if (_productos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Primero cargá al menos un producto desde "Productos".')));
      return;
    }
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ConstructorPlanDialog(planId: _plan!.id, productos: _productos),
    );
    if (guardado == true) _cargar();
  }

  /// Si [d] ya está completado (por ejemplo, porque Jarabes lo marcó solo
  /// al finalizar el preparado con una estimación), reabre este mismo
  /// diálogo precargado con lo que ya se guardó, para corregir botellas o
  /// merma con el dato real una vez que se termina de embotellar — no
  /// vuelve a descontar stock (el trigger del servidor solo descuenta en
  /// la primera vez que pasa a completado).
  Future<void> _marcarCompletado(PlanProduccionDetalle d) async {
    final usuario = context.read<AuthService>().usuarioActual!;
    final estimado = d.litrosPorBotella != null && d.litrosPorBotella! > 0
        ? (d.litrosPlanificados / d.litrosPorBotella!).round()
        : null;
    // fmtNum(null) devuelve "-" (para mostrar en pantalla), que no es un
    // número válido para precargar un campo editable: si se guardaba sin
    // tocarlo, pisaba el dato real con 0. Acá, sin dato, el campo queda
    // vacío en vez de con ese guion.
    final botellasCtrl = TextEditingController(
        text: d.completado
            ? (d.botellasProducidas == null
                ? ''
                : d.botellasProducidas!.toStringAsFixed(0))
            : (estimado?.toString() ?? ''));
    final mermaCtrl = TextEditingController(
        text: d.completado ? d.mermaLitros.toStringAsFixed(0) : '0');

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(d.completado ? 'Corregir producción' : 'Marcar como completado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.completado
                ? 'Corregí botellas o merma con el dato real, si la estimación no fue exacta. '
                    'Esto NO vuelve a ajustar el descuento de stock (ya se hizo con el número '
                    'anterior) — si la diferencia es grande, avisale a Almacén para que la '
                    'corrija a mano.'
                : 'Se descontará automáticamente la materia prima de "${d.sabor}"'
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
              child: Text(d.completado ? 'Guardar' : 'Confirmar')),
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
    final usuario = context.read<AuthService>().usuarioActual!;
    await showDialog(
      context: context,
      builder: (_) => ProduccionCapturaDialog(plan: _plan!, usuario: usuario),
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
          Row(
            children: [
              const Expanded(
                child: Text('Producción del día',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              BotonAyuda(idTour: 'produccion_del_dia', pasos: _pasosAyuda),
            ],
          ),
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
                _pasoArmarPlan.envolver(
                  FilledButton.icon(
                    style:
                        FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: _armarPlan,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Armar plan'),
                  ),
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
          if (widget.onIrAJarabes != null) ...[
            const SizedBox(height: 4),
            Text('Tocá el ícono de gota, o el producto, para ir a Jarabes con '
                'ese sabor listo para calcular el preparado.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _pasoLista.envolver(
              _plan == null || _plan!.detalle.isEmpty
                  ? const Center(child: Text('Aún no hay productos planificados hoy.'))
                  : ListView(
                    children: _plan!.detalle
                        .map((d) => Card(
                              child: ListTile(
                                onTap: widget.onIrAJarabes == null
                                    ? null
                                    : () => widget.onIrAJarabes!(d.sabor),
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.onIrAJarabes != null)
                                      IconButton(
                                        tooltip: 'Ir a Jarabes a calcular el preparado',
                                        icon: const Icon(Icons.water_drop_outlined,
                                            color: AppColors.primario),
                                        onPressed: () => widget.onIrAJarabes!(d.sabor),
                                      ),
                                    if (d.completado)
                                      usuario.puedeEditarProduccion
                                          ? ActionChip(
                                              label: const Text('Completado'),
                                              avatar: const Icon(Icons.edit_outlined, size: 16),
                                              onPressed: () => _marcarCompletado(d),
                                            )
                                          : const Chip(label: Text('Completado'))
                                    else if (usuario.puedeEditarProduccion)
                                      ElevatedButton(
                                        onPressed: () => _marcarCompletado(d),
                                        child: const Text('Marcar hecho'),
                                      )
                                    else
                                      const Text('Pendiente',
                                          style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
