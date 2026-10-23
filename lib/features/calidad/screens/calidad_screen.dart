import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
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

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoPendientes = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Pendientes de analizar',
    texto: 'Los preparados que Jarabes ya finalizó y todavía no tienen análisis de '
        'Calidad (Brix, pH, aspecto).',
  );
  final _pasoHistorial = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Historial',
    texto: 'Los análisis ya hechos, marcados como conforme o no conforme.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'calidad', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoPendientes, _pasoHistorial];

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

    // El historial de análisis puede crecer mucho: queda como lista
    // perezosa aparte, después del encabezado (que se construye entero de
    // entrada para que el tour siempre encuentre sus pasos).
    // Lista perezosa (ListView.builder): cada tarjeta del historial se crea
    // recién cuando aparece en pantalla, no las ~200 de una vez al entrar. El
    // encabezado es el ítem 0 y se construye entero, así el tour siempre
    // encuentra sus pasos.
    final lista = svc.analisis;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 1 + (lista.isEmpty ? 1 : lista.length),
      itemBuilder: (context, i) {
        if (i == 0) return _encabezado(svc);
        if (lista.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay análisis registrados.',
                style: TextStyle(color: Colors.black54)),
          );
        }
        final a = lista[i - 1];
        return _TarjetaAnalisis(svc: svc, a: a);
      },
    );
  }

  Widget _encabezado(CalidadService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(
            child: Text('Control de Calidad',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          BotonAyuda(idTour: 'calidad', pasos: _pasosAyuda),
        ]),
        const SizedBox(height: 16),
        _pasoPendientes.envolver(
          Text('Pendientes de analizar (${svc.pendientes.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
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
        _pasoHistorial.envolver(
          const Text('Historial',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(height: 8),
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
