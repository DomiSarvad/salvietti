import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../models/produccion.dart';
import '../../../services/auth_service.dart';
import '../../../services/produccion_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../../../utils/texto.dart';
import '../models/jarabes_modelos.dart';
import '../repositories/jarabes_repository.dart';
import '../services/jarabes_service.dart';
import '../widgets/finalizar_preparado_dialog.dart';
import '../widgets/iniciar_preparado_dialog.dart';
import '../widgets/proponer_receta_dialog.dart';
import '../widgets/resolver_receta_dialog.dart';

/// Producción de Jarabes: preparados en curso e historial, avance de
/// Soplado y, si corresponde, recetas propuestas por aprobar. Solo UI; las
/// reglas viven en el service.
class JarabesScreen extends StatelessWidget {
  /// Si viene de "Producción del día" con un producto tocado, el nombre de
  /// su sabor: al entrar, abre "Nuevo preparado" ya con ese sabor elegido
  /// y verificando insumos, listo para calcular.
  final String? saborInicial;
  const JarabesScreen({super.key, this.saborInicial});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => JarabesService(SupabaseJarabesRepository(), usuario)..iniciar(),
      child: _Vista(saborInicial: saborInicial),
    );
  }
}

class _Vista extends StatefulWidget {
  final String? saborInicial;
  const _Vista({this.saborInicial});

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  PlanProduccion? _plan;
  bool _cargandoPlan = true;
  bool _autoAbierto = false;

  @override
  void initState() {
    super.initState();
    _cargarPlan();
  }

  /// El plan del día (de Producción, un subsistema aparte) se muestra acá
  /// solo como referencia: qué sabor conviene preparar hoy. No restringe
  /// nada — un preparado se puede iniciar con cualquier sabor, porque
  /// durante el día puede cambiar lo que hace falta.
  Future<void> _cargarPlan() async {
    final usuario = context.read<AuthService>().usuarioActual!;
    try {
      final plan = await ProduccionService.planDeHoy(usuario.id);
      if (mounted) setState(() => _plan = plan);
    } catch (_) {
      // Sin plan de hoy o sin conexión: la referencia simplemente no se
      // muestra, Jarabes sigue funcionando igual.
    }
    if (mounted) setState(() => _cargandoPlan = false);
  }

  Set<String> get _saboresEnPlanHoy => {
        for (final d in _plan?.detalle ?? const <PlanProduccionDetalle>[]) sinTildes(d.sabor),
      };

  bool _esHoy(DateTime d) {
    final hoy = DateTime.now();
    return d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
  }

  /// Sabores que Jarabes YA preparó hoy (con un preparado finalizado),
  /// independiente del "completado" de Producción — ese lo tilda quien
  /// termina de embotellar, no Jarabes. Esto es para que, en la propia
  /// pantalla de Jarabes, quede claro qué ya se hizo hoy sin depender de
  /// que el cruce con el plan haya encontrado o no una fila para marcar.
  Set<String> _saboresYaPreparadosHoy(JarabesService svc) => {
        for (final p in svc.preparados)
          if (p.estado == EstadoPreparado.finalizada && p.sabor != null && _esHoy(p.fecha))
            sinTildes(p.sabor!),
      };

  Future<void> _iniciar(BuildContext context, JarabesService svc, {Sabor? saborInicial}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => IniciarPreparadoDialog(
            servicio: svc, saboresEnPlanHoy: _saboresEnPlanHoy, saborInicial: saborInicial),
      );

  Future<void> _proponerReceta(BuildContext context, JarabesService svc) => showDialog<bool>(
        context: context,
        builder: (_) => ProponerRecetaDialog(servicio: svc),
      );

  Sabor? _buscarSaborPorNombre(JarabesService svc, String nombre) {
    final buscado = sinTildes(nombre);
    for (final s in svc.sabores) {
      if (sinTildes(s.nombre) == buscado) return s;
    }
    return null;
  }

  /// Viniendo de "Producción del día" con un sabor tocado: lo busca en el
  /// catálogo de Jarabes por nombre y abre "Nuevo preparado" ya con ese
  /// sabor elegido. Se dispara una sola vez por entrada a la pantalla —
  /// para volver a abrirlo después (si se cerró sin querer, o para preparar
  /// otro del mismo plan) está el mismo botón en la tarjeta "Plan de hoy".
  void _abrirAutoSiCorresponde(BuildContext context, JarabesService svc) {
    if (_autoAbierto || widget.saborInicial == null || !svc.puedeIniciar) return;
    _autoAbierto = true;
    final preseleccionado = _buscarSaborPorNombre(svc, widget.saborInicial!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _iniciar(context, svc, saborInicial: preseleccionado);
    });
  }

  /// Igual que arriba, pero se puede repetir todas las veces que haga
  /// falta: tocar un producto de "Plan de hoy" siempre abre "Nuevo
  /// preparado" con ese sabor, aunque ya se haya usado o cerrado antes.
  void _iniciarDesdePlan(BuildContext context, JarabesService svc, String sabor) =>
      _iniciar(context, svc, saborInicial: _buscarSaborPorNombre(svc, sabor));

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<JarabesService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVerProduccion) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Jarabes.'),
        ),
      );
    }
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
        ]),
      );
    }

    _abrirAutoSiCorresponde(context, svc);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Jarabes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (svc.puedeProponerReceta)
              OutlinedButton.icon(
                onPressed: () => _proponerReceta(context, svc),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Proponer receta'),
              ),
            const SizedBox(width: 8),
            if (svc.puedeIniciar)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _iniciar(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo preparado'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_cargandoPlan && _plan != null && _plan!.detalle.isNotEmpty) ...[
          _SeccionPlanDelDia(
            plan: _plan!,
            puedeIniciar: svc.puedeIniciar,
            onPreparar: (sabor) => _iniciarDesdePlan(context, svc, sabor),
            saboresYaPreparados: _saboresYaPreparadosHoy(svc),
          ),
          const SizedBox(height: 20),
        ],
        if (svc.puedeAprobarReceta && svc.recetasPendientes.isNotEmpty) ...[
          _SeccionRecetasPendientes(svc: svc),
          const SizedBox(height: 20),
        ],
        _SeccionAvanceSoplado(svc: svc),
        const SizedBox(height: 20),
        if (svc.enCurso.isNotEmpty) ...[
          const Text('En curso', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          for (final p in svc.enCurso)
            _TarjetaPreparado(svc: svc, p: p, planHoy: _plan, onFinalizado: _cargarPlan),
          const SizedBox(height: 20),
        ],
        const Text('Historial', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (svc.historial.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay preparados finalizados.',
                style: TextStyle(color: Colors.black54)),
          )
        else
          for (final p in svc.historial) _TarjetaPreparado(svc: svc, p: p),
      ],
    );
  }
}

/// Referencia de solo lectura: qué planificó el Jefe de Producción para
/// hoy (subsistema aparte, `ProduccionService`). No restringe nada — sirve
/// para saber qué sabor conviene preparar sin salir de Jarabes; si durante
/// el día hace falta otro, "Nuevo preparado" igual deja elegir cualquiera.
/// Cada fila se puede tocar (todas las veces que haga falta) para abrir
/// "Nuevo preparado" con ese sabor ya elegido — así, si el diálogo se
/// cerró sin querer, alcanza con volver a tocar el producto.
class _SeccionPlanDelDia extends StatelessWidget {
  final PlanProduccion plan;
  final bool puedeIniciar;
  final void Function(String sabor) onPreparar;
  /// Sabores (normalizados con [sinTildes]) que Jarabes ya preparó hoy —
  /// para avisarle a quien prepara que ese paso ya está hecho, aunque el
  /// producto siga "pendiente" acá (eso lo tilda quien termina de
  /// embotellar, no Jarabes).
  final Set<String> saboresYaPreparados;
  const _SeccionPlanDelDia({
    required this.plan,
    required this.puedeIniciar,
    required this.onPreparar,
    this.saboresYaPreparados = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFF0F7F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCFE6D8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.factory_outlined, size: 18, color: AppColors.primario),
            SizedBox(width: 8),
            Text('Plan de hoy (Producción)', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Text(
              puedeIniciar
                  ? 'De referencia: guía qué sabor conviene preparar. Tocá un producto para '
                      'abrir "Nuevo preparado" con ese sabor.'
                  : 'De referencia: guía qué sabor conviene preparar.',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final d in plan.detalle)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: puedeIniciar ? () => onPreparar(d.sabor) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(d.completado ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: d.completado ? const Color(0xFF16A34A) : Colors.black38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(d.nombreProducto ?? d.sabor,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (!d.completado && saboresYaPreparados.contains(sinTildes(d.sabor))) ...[
                        const Icon(Icons.water_drop, size: 12, color: Color(0xFF2563EB)),
                        const SizedBox(width: 3),
                        const Text('Jarabes listo',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2563EB))),
                        const SizedBox(width: 8),
                      ],
                      Text('${fmtNum(d.litrosPlanificados, decimales: 0)} L',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      if (puedeIniciar) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.play_circle_outline,
                            size: 16, color: AppColors.primario),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SeccionAvanceSoplado extends StatelessWidget {
  final JarabesService svc;
  const _SeccionAvanceSoplado({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Avance de Soplado (últimos 14 días)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (svc.avanceSoplado.isEmpty)
            const Text('Sin corridas de soplado registradas en este período.',
                style: TextStyle(color: Colors.black54))
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final a in svc.avanceSoplado)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
                    child: Text('${a.sabor} · ${a.presentacion}: '
                        '${fmtNum(a.cajasSopladas, decimales: 0)} cajas',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SeccionRecetasPendientes extends StatelessWidget {
  final JarabesService svc;
  const _SeccionRecetasPendientes({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF8E8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0D28B))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recetas por aprobar (${svc.recetasPendientes.length})',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final r in svc.recetasPendientes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r.sabor ?? ''),
              subtitle: Text('Propuesta por ${r.creadaPorNombre ?? '—'} · '
                  '${r.items.length} insumo${r.items.length == 1 ? '' : 's'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<bool>(
                context: context,
                builder: (_) => ResolverRecetaDialog(servicio: svc, receta: r),
              ),
            ),
        ],
      ),
    );
  }
}

class _TarjetaPreparado extends StatelessWidget {
  final JarabesService svc;
  final Preparado p;
  final PlanProduccion? planHoy;
  /// Se llama al cerrar el diálogo de finalizar (haya quedado marcado el
  /// plan o no), para refrescar "Plan de hoy" y que se vea al toque el
  /// aviso "Jarabes listo" / el tilde, sin tener que salir y volver a
  /// entrar a la pantalla.
  final VoidCallback? onFinalizado;
  const _TarjetaPreparado({required this.svc, required this.p, this.planHoy, this.onFinalizado});

  Color _color() {
    switch (p.estado) {
      case EstadoPreparado.enCurso:
        return const Color(0xFFD97706);
      case EstadoPreparado.finalizada:
        return const Color(0xFF16A34A);
      case EstadoPreparado.anulada:
        return Colors.black45;
    }
  }

  Future<void> _finalizar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => FinalizarPreparadoDialog(servicio: svc, preparado: p, planHoy: planHoy),
    );
    if (ok == true) onFinalizado?.call();
  }

  Future<void> _anular(BuildContext context) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Anular preparado'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Anular')),
          ],
        );
      },
    );
    if (motivo == null || !context.mounted) return;
    final error = await svc.anularPreparado(p, motivo);
    if (!context.mounted) return;
    error == null ? mostrarExito(context, 'Preparado anulado.') : mostrarError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${p.sabor ?? ''} · Lote ${p.nLote}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _color().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(p.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: _color())),
                ),
              ],
            ),
            Text(
              p.horaFin == null
                  ? 'Inicio: ${fmtFechaHora(p.horaInicio)} · ${p.responsableNombre ?? '—'}'
                  : 'Inicio: ${fmtFechaHora(p.horaInicio)} · Fin: ${fmtFechaHora(p.horaFin)} '
                      '(${p.duracion!.inMinutes} min) · ${p.responsableNombre ?? '—'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _pill('${fmtNum(p.cantidadPreparados, decimales: 2)} preparado(s)', AppColors.negro),
              if (p.litros != null) _pill('${fmtNum(p.litros, decimales: 0)} L', AppColors.primario),
              if (p.tanque != null) _pill('Tanque ${p.tanque}', Colors.black54),
              if (p.brix != null) _pill('Brix ${fmtNum(p.brix, decimales: 1)}', const Color(0xFF5BC0DE)),
            ]),
            if (p.observaciones != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(p.observaciones!),
              ),
            if (p.estado == EstadoPreparado.enCurso && svc.puedeFinalizar) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                    onPressed: () => _finalizar(context),
                    child: const Text('Finalizar')),
                TextButton(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                    onPressed: () => _anular(context),
                    child: const Text('Anular')),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}
