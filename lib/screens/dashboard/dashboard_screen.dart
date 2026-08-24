import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/insumo.dart';
import '../../models/produccion.dart';
import '../../services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../services/produccion_service.dart';
import '../../widgets/stock_status_badge.dart';
import '../produccion/produccion_planner_screen.dart';

/// Pantalla principal: lo primero que ve cualquier rol al entrar.
/// Combina el plan de producción del día (lo que el ingeniero organizó)
/// con el medidor de salud del inventario y las alertas de stock/vencimiento,
/// tal como piden los casos de uso 4 y 6.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Insumo> _insumos = [];
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
    PlanProduccion? plan;
    try {
      plan = await ProduccionService.planDeHoy(usuario.id);
    } catch (_) {
      plan = null;
    }
    if (!mounted) return;
    setState(() {
      _insumos = insumos;
      _plan = plan;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final criticos =
        _insumos.where((i) => i.diasExistencia <= 3).toList()
          ..sort((a, b) => a.diasExistencia.compareTo(b.diasExistencia));
    final bajos = _insumos
        .where((i) => i.diasExistencia > 3 && i.diasExistencia <= 7)
        .toList();
    final optimos = _insumos.length - criticos.length - bajos.length;

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
              _tarjetaResumen('Insumos ÓPTIMOS', optimos, EstadoStock.optimo),
              _tarjetaResumen('Insumos BAJOS', bajos.length, EstadoStock.bajo),
              _tarjetaResumen(
                  'Insumos CRÍTICOS', criticos.length, EstadoStock.critico),
            ],
          ),
          const SizedBox(height: 24),
          if (_plan != null) _cardPlanDelDia(_plan!),
          const SizedBox(height: 24),
          _cardInsumosEnRiesgo(criticos.take(8).toList()),
        ],
      ),
    );
  }

  Widget _tarjetaResumen(String titulo, int valor, EstadoStock estado) {
    final color = SemaforoStock.color(estado);
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
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 8),
          Text('$valor',
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, color: color)),
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
              const Text('Plan de producción de hoy',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
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
                  title: Text(d.sabor),
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
              Text('Insumos en riesgo de desabastecimiento',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
}
