import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/produccion.dart';
import '../../models/usuario.dart';
import '../../services/auth_service.dart';
import '../../services/produccion_service.dart';
import '../../services/sync_service.dart';
import '../../shared/ayuda/tour_ayuda.dart';
import '../../shared/check_animado.dart';
import '../../shared/pagina_o_dialogo.dart';
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
    texto: 'Cargá los productos del día y compartí la foto.',
  );
  final _pasoLista = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Marcar como completado',
    texto: 'Tocá "Marcar hecho" al terminar cada producto.',
  );
  // Para quien solo mira el plan (Gerente, las áreas): no tilda nada.
  final _pasoListaVer = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Plan de hoy',
    texto: 'Qué se produce hoy y qué ya se terminó.',
  );

  StreamSubscription<void>? _alVolverRed;

  bool get _editor => context.read<AuthService>().usuarioActual?.puedeEditarProduccion ?? false;
  PasoAyuda get _pasoListaActual => _editor ? _pasoLista : _pasoListaVer;

  @override
  void initState() {
    super.initState();
    // El tour recién después de cargar: mientras carga solo hay un spinner y
    // sus pasos no estarían montados (mismo caso que Jarabes).
    _cargar().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TourAyuda.mostrar(context,
              idTour: 'produccion_del_dia', soloSiNoVisto: true, pasos: _pasosAyuda());
        }
      });
    });
    // Volvió internet o se subió la cola: lo que se ve puede ser la copia vieja.
    _alVolverRed = context.read<SyncService>().alHaberDatosNuevos.listen((_) {
      if (mounted && !_cargando) _cargar();
    });
  }

  @override
  void dispose() {
    _alVolverRed?.cancel();
    super.dispose();
  }

  List<PasoAyuda> _pasosAyuda() => [if (_editor) _pasoArmarPlan, _pasoListaActual];

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
    final guardado = await abrirAdaptable<bool>(
      context,
      (_) => ConstructorPlanDialog(planId: _plan!.id, productos: _productos),
    );
    if (guardado != true) return;
    // Lo de siempre después de armar el plan: mandarlo por WhatsApp a planta.
    // Se abre solo, con el plan ya recargado (la foto sale de lo guardado).
    await _cargar();
    if (mounted && _plan != null && _plan!.detalle.isNotEmpty) await _guardarImagen();
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
    await abrirAdaptable(context, (_) => const ProductosCatalogoDialog());
    _cargar();
  }

  Future<void> _abrirEditarConsumo() async {
    await abrirAdaptable(context, (_) => const EditarConsumoDialog());
  }

  Future<void> _guardarImagen() async {
    if (_plan == null) return;
    final usuario = context.read<AuthService>().usuarioActual!;
    await showDialog(
      context: context,
      builder: (_) => ProduccionCapturaDialog(plan: _plan!, usuario: usuario),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;

    if (_cargando) return const Center(child: CircularProgressIndicator());

    final angosto = MediaQuery.sizeOf(context).width < 600;
    // Toda la pantalla se desplaza (antes el encabezado quedaba fijo y en un
    // celular la lista se reducía a una franja de pocos píxeles). La lista del
    // día es corta, así que una lista común (no .builder) alcanza, y así el
    // tour encuentra todo montado.
    return ListView(
      padding: EdgeInsets.all(angosto ? 16 : 24),
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
          // Quien no arma el plan (Gerente, las áreas) solo lo mira: no ve
          // botones. Compartir es para mandarlo a planta por
          // WhatsApp, y eso lo hace el Jefe de Producción.
          if (usuario.puedeEditarProduccion)
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
            ),
          const SizedBox(height: 4),
          Text(
              usuario.puedeEditarProduccion
                  ? 'Marca cada producto cuando termine de embotellarse: el sistema '
                      'descuenta automáticamente materia prima, preformas y tapas '
                      'según la receta y las botellas producidas.'
                  : 'Lo que se va a producir hoy. El Jefe de Producción lo va marcando '
                      'a medida que se termina.',
              style: TextStyle(color: Colors.grey.shade600)),
          if (_irAJarabes(usuario) != null) ...[
            const SizedBox(height: 4),
            Text('Tocá el ícono de gota, o el producto, para ir a Jarabes con '
                'ese sabor listo para calcular el preparado.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          _pasoListaActual.envolver(
            _plan == null || _plan!.detalle.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Aún no hay productos planificados hoy.')),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final d in _plan!.detalle) _tarjeta(d, usuario)],
                  ),
          ),
      ],
    );
  }

  /// Una tarjeta por producto. Antes era un `ListTile` con el ícono de gota y
  /// "Marcar hecho" en `trailing`: en un celular esos botones se quedaban con
  /// todo el ancho y el nombre del producto se partía letra por letra. Ahora
  /// el texto va arriba a todo el ancho y las acciones en un `Wrap` abajo.
  /// El atajo a Jarabes es para quien trabaja con el plan; el Gerente (solo
  /// informes) no prepara jarabe, y Jarabes ni está en su menú.
  void Function(String sabor)? _irAJarabes(Usuario usuario) =>
      usuario.soloInformes ? null : widget.onIrAJarabes;

  Widget _tarjeta(PlanProduccionDetalle d, Usuario usuario) {
    final ir = _irAJarabes(usuario);
    final irAJarabes = ir == null ? null : () => ir(d.sabor);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: irAJarabes,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    d.completado ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: d.completado ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.nombreProducto ?? d.sabor,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          d.completado
                              ? '${fmtNum(d.botellasProducidas, decimales: 0)} botellas producidas'
                                  '${d.mermaLitros > 0 ? ' · merma: ${fmtNum(d.mermaLitros, decimales: 0)} L' : ''}'
                              : '${fmtNum(d.litrosPlanificados, decimales: 0)} litros planificados',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (irAJarabes != null)
                    TextButton.icon(
                      onPressed: irAJarabes,
                      icon: const Icon(Icons.water_drop_outlined, size: 18),
                      label: const Text('Jarabes'),
                    ),
                  if (d.completado)
                    usuario.puedeEditarProduccion
                        ? ActionChip(
                            label: const Text('Completado'),
                            // El ✓ se dibuja al aparecer; tocar el chip corrige lo cargado.
                            avatar: const CheckAnimado(tamano: 18, grosor: 2.5),
                            onPressed: () => _marcarCompletado(d),
                          )
                        : const Chip(
                            label: Text('Completado'),
                            avatar: CheckAnimado(tamano: 18, grosor: 2.5),
                          )
                  else if (usuario.puedeEditarProduccion)
                    FilledButton(
                      onPressed: () => _marcarCompletado(d),
                      child: const Text('Marcar hecho'),
                    )
                  else
                    const Text('Pendiente', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
