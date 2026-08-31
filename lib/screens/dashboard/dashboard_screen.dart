import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../models/movimiento.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../services/movimiento_service.dart';
import '../../services/produccion_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/stock_status_badge.dart';
import '../produccion/produccion_planner_screen.dart';

/// Pantalla principal: lo primero que ve cualquier rol al entrar.
/// Combina el plan de producción del día, el estado óptimo/crítico de
/// cada categoría de inventario y los movimientos (entradas/salidas)
/// más recientes. Jarabes solo ve su propia área.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Insumo> _insumos = [];
  List<Movimiento> _movimientos = [];
  PlanProduccion? _plan;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final usuario = context.read<AuthService>().usuarioActual!;
    final insumos = await InventarioService.listarTodo();
    final movimientos = await MovimientoService.listarRecientes();
    PlanProduccion? plan;
    try {
      plan = await ProduccionService.planDeHoy(usuario.id);
    } catch (_) {
      plan = null;
    }
    if (!mounted) return;
    setState(() {
      _insumos = insumos;
      _movimientos = movimientos;
      _plan = plan;
      _cargando = false;
    });
  }

  List<Insumo> _porCategoria(String tabla, {bool soloJarabes = false}) =>
      _insumos
          .where((i) =>
              i.tabla == tabla && (!soloJarabes || i.area == 'jarabes'))
          .toList();

  @override
  Widget build(BuildContext context) {
    final usuario = context.watch<AuthService>().usuarioActual!;
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final tapas = _porCategoria('tapas');
    final preformas = _porCategoria('preformas');
    final materiaPrimaGeneral = _porCategoria('materia_prima')
        .where((i) => i.area != 'jarabes')
        .toList();
    final jarabes = _porCategoria('materia_prima', soloJarabes: true);

    final insumosVisibles = usuario.esJarabes
        ? jarabes
        : [...tapas, ...preformas, ...materiaPrimaGeneral, ...jarabes];
    final criticosVisibles = insumosVisibles
        .where((i) => i.diasExistencia <= 3)
        .toList()
      ..sort((a, b) => a.diasExistencia.compareTo(b.diasExistencia));

    final movimientosVisibles = usuario.esJarabes
        ? _movimientos.where((m) {
            if (m.tablaOrigen != 'materia_prima') return false;
            final item = _insumos.where((i) => i.id == m.itemId).firstOrNull;
            return item?.area == 'jarabes';
          }).toList()
        : _movimientos;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Dashboard Ejecutivo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (!usuario.esJarabes) ...[
                _tarjetaCategoria('Tapas', tapas),
                _tarjetaCategoria('Preformas', preformas),
                _tarjetaCategoria('Materia Prima', materiaPrimaGeneral),
              ],
              _tarjetaCategoria('Jarabes', jarabes),
            ],
          ),
          const SizedBox(height: 24),
          if (_plan != null) _cardPlanDelDia(_plan!),
          const SizedBox(height: 24),
          _cardInsumosEnRiesgo(criticosVisibles.take(8).toList()),
          const SizedBox(height: 24),
          _cardMovimientosRecientes(movimientosVisibles, usuario.esAlmacen),
        ],
      ),
    );
  }

  Widget _tarjetaCategoria(String titulo, List<Insumo> items) {
    // Sin ítems todavía (ej. "Jarabes" antes de que Almacén marque algo
    // como su área) no es lo mismo que "todo óptimo": mostrarlo en verde
    // como si el stock estuviera sano sería engañoso. Se muestra en gris
    // y se aclara que falta cargar/marcar datos.
    if (items.isEmpty) {
      const color = Colors.black38;
      return Container(
        width: 240,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: const Border(left: BorderSide(color: color, width: 5)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Sin datos',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            const Text('Todavía no hay ítems cargados en esta categoría.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      );
    }

    final criticos = items.where((i) => i.diasExistencia <= 3).length;
    final bajos = items
        .where((i) => i.diasExistencia > 3 && i.diasExistencia <= 7)
        .length;
    final optimos = items.length - criticos - bajos;
    final estadoPeor = criticos > 0
        ? EstadoStock.critico
        : (bajos > 0 ? EstadoStock.bajo : EstadoStock.optimo);
    final color = SemaforoStock.color(estadoPeor);

    return Container(
      width: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${items.length}',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 6),
          Text('$optimos óptimos · $bajos bajos · $criticos críticos',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _cardPlanDelDia(PlanProduccion plan) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.factory_outlined, color: AppColors.primario),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Plan de producción de hoy',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ProduccionPlannerScreen())),
                child: const Text('Ver todo →'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (plan.detalle.isEmpty)
            const Text('El Jefe de Producción aún no planificó el día.',
                style: TextStyle(color: Colors.black54))
          else
            ...plan.detalle.map((d) => ListTile(
                  dense: true,
                  leading: Icon(
                      d.completado
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: d.completado ? Colors.green : Colors.grey),
                  title: Text(d.nombreProducto ?? d.sabor),
                  trailing: Text('${d.litrosPlanificados.toStringAsFixed(0)} L'),
                )),
        ],
      ),
    );
  }

  Widget _cardInsumosEnRiesgo(List<Insumo> criticos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('Insumos en riesgo de desabastecimiento',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (criticos.isEmpty)
            const Text('No hay insumos críticos por el momento. 🎉',
                style: TextStyle(color: Colors.black54))
          else
            ...criticos.map((i) => ListTile(
                  dense: true,
                  title: Text(i.detalle),
                  subtitle: Text('${i.codigo} · ${i.tabla}'),
                  trailing: StockStatusBadge(diasExistencia: i.diasExistencia),
                )),
        ],
      ),
    );
  }

  Widget _cardMovimientosRecientes(List<Movimiento> movimientos, bool puedeDeshacer) {
    final idsRevertidos =
        _movimientos.map((m) => m.revierteMovimientoId).whereType<String>().toSet();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.swap_vert, color: AppColors.primario),
              SizedBox(width: 8),
              Expanded(
                child: Text('Movimientos recientes',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (movimientos.isEmpty)
            const Text('Todavía no hay movimientos registrados.',
                style: TextStyle(color: Colors.black54))
          else
            ...movimientos.take(10).map((m) {
              final item = _insumos.where((i) => i.id == m.itemId).firstOrNull;
              final esIngreso = m.tipo == 'ingreso';
              final yaRevertido = idsRevertidos.contains(m.id);
              final esReversion = m.revierteMovimientoId != null;
              final elegible = !yaRevertido &&
                  MovimientoService.puedeDeshacerse(m, item?.cantidadReal ?? 0);

              return ListTile(
                dense: true,
                leading: Icon(
                    esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                    color: esIngreso ? Colors.green : Colors.orange,
                    size: 18),
                title: Text(item?.detalle ?? m.itemId),
                subtitle: Text(esReversion
                    ? '${fmtFechaHora(m.creadoEn)} · corrección'
                    : (yaRevertido
                        ? '${fmtFechaHora(m.creadoEn)} · deshecho'
                        : fmtFechaHora(m.creadoEn))),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        '${esIngreso ? '+' : '-'}${fmtNum(m.cantidad, decimales: 0)} ${m.unidadMedida ?? ''}'),
                    if (puedeDeshacer && !esReversion && !yaRevertido) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        tooltip: elegible
                            ? 'Deshacer este movimiento'
                            : 'Cantidad demasiado grande para deshacer con un clic',
                        color: elegible ? Colors.black54 : Colors.black26,
                        onPressed: () => _confirmarDeshacer(m, item, elegible),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _confirmarDeshacer(Movimiento m, Insumo? item, bool elegible) async {
    if (!elegible) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se puede deshacer automáticamente'),
          content: const Text(
              'Esta cantidad es demasiado grande en relación al stock actual '
              'del ítem. Para evitar corregir por accidente un movimiento '
              'grande real, este tipo de corrección se hace con un ajuste '
              'manual desde Inventario, no con un clic.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }
    final usuario = context.read<AuthService>().usuarioActual!;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deshacer movimiento'),
        content: Text(
            'Se registrará una corrección que revierte '
            '${m.tipo == 'ingreso' ? 'la entrada' : 'la salida'} de '
            '${fmtNum(m.cantidad, decimales: 0)} ${m.unidadMedida ?? ''} de '
            '"${item?.detalle ?? m.itemId}". El movimiento original queda '
            'en el historial, marcado como corregido.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deshacer')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await MovimientoService.deshacer(
        movimiento: m,
        cantidadActualItem: item?.cantidadReal ?? 0,
        usuarioId: usuario.id,
      );
      if (mounted) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo deshacer: $e')));
      }
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
