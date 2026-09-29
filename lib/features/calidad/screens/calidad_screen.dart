import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';
import '../models/calidad_modelos.dart';
import '../repositories/calidad_repository.dart';
import '../services/calidad_service.dart';
import '../widgets/actualizar_analisis_dialog.dart';
import '../widgets/analisis_form_dialog.dart';

/// Control de Calidad: preparados de Jarabes pendientes de analizar, e
/// historial de análisis. Solo UI; las reglas viven en el service.
class CalidadScreen extends StatelessWidget {
  const CalidadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => CalidadService(SupabaseCalidadRepository(), usuario)..iniciar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatelessWidget {
  const _Vista();

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CalidadService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Control de Calidad.'),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Control de Calidad',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Text('Pendientes de analizar (${svc.pendientes.length})',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (svc.pendientes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No hay preparados esperando análisis.',
                style: TextStyle(color: Colors.black54)),
          )
        else
          for (final p in svc.pendientes) _TarjetaPendiente(svc: svc, p: p),
        const SizedBox(height: 20),
        const Text('Historial', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (svc.analisis.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay análisis registrados.',
                style: TextStyle(color: Colors.black54)),
          )
        else
          for (final a in svc.analisis) _TarjetaAnalisis(svc: svc, a: a),
      ],
    );
  }
}

class _TarjetaPendiente extends StatelessWidget {
  final CalidadService svc;
  final PreparadoPendiente p;
  const _TarjetaPendiente({required this.svc, required this.p});

  Future<void> _analizar(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => AnalisisFormDialog(servicio: svc, preparado: p),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: p.brixFueraDeRango ? const Color(0xFFFFF8E8) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.sabor} · Lote ${p.nLote}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    'Finalizado: ${p.horaFin == null ? '—' : fmtFechaHora(p.horaFin)} · '
                    'Brix: ${p.brix == null ? '—' : fmtNum(p.brix, decimales: 1)}'
                    '${p.brixFueraDeRango ? ' (fuera de rango)' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: p.brixFueraDeRango ? const Color(0xFFB03030) : Colors.black54),
                  ),
                ],
              ),
            ),
            if (svc.puedeCrear)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _analizar(context),
                child: const Text('Analizar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAnalisis extends StatelessWidget {
  final CalidadService svc;
  final AnalisisCalidad a;
  const _TarjetaAnalisis({required this.svc, required this.a});

  Future<void> _editar(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => ActualizarAnalisisDialog(servicio: svc, analisis: a),
      );

  @override
  Widget build(BuildContext context) {
    final color = a.conforme ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
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
                  child: Text('${a.sabor ?? ''}${a.nLote == null ? '' : ' · Lote ${a.nLote}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(a.conforme ? 'Conforme' : 'No conforme',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                ),
              ],
            ),
            Text('${fmtFechaHora(a.fecha)} · ${a.responsableNombre ?? '—'}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (a.brixDiluido != null)
                _pill('Brix diluido: ${fmtNum(a.brixDiluido, decimales: 1)}', AppColors.negro),
              if (a.ph != null) _pill('pH: ${fmtNum(a.ph, decimales: 1)}', AppColors.negro),
              if (a.aspecto != null) _pill(a.aspecto!, Colors.black54),
            ]),
            if (a.accionTomada != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Acción tomada: ${a.accionTomada}',
                    style: const TextStyle(fontSize: 13)),
              ),
            if (a.observaciones != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(a.observaciones!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            if (svc.puedeEditar) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _editar(context), child: const Text('Editar')),
              ),
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
