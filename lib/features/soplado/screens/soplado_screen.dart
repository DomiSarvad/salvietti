import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/soplado_modelos.dart';
import '../repositories/soplado_repository.dart';
import '../services/soplado_service.dart';
import '../widgets/finalizar_corrida_dialog.dart';
import '../widgets/iniciar_corrida_dialog.dart';
import '../../../shared/chip_sin_subir.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Producción de Soplado: corridas en curso, historial y el avance de los
/// últimos 14 días (lo ven también Jarabes y Producción). Solo UI; las
/// reglas viven en el service.
class SopladoScreen extends StatelessWidget {
  const SopladoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => SopladoService(SupabaseSopladoRepository(), usuario)..iniciar(),
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
  final _pasoIniciar = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Iniciar corrida',
    texto: 'Sabor, presentación y lote de preforma.',
  );
  final _pasoAvance = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Avance de los últimos 14 días',
    texto: 'Lo soplado en las últimas dos semanas.',
  );
  final _pasoHistorial = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Historial',
    texto: 'Corridas cerradas, con su merma.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'soplado', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoIniciar, _pasoAvance, _pasoHistorial];

  Future<void> _iniciar(BuildContext context, SopladoService svc) => showDialog<bool>(
        context: context,
        builder: (_) => IniciarCorridaDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SopladoService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Soplado.'),
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

    // El historial puede crecer mucho: sigue siendo una lista perezosa,
    // aparte, después del bloque de arriba (que se construye entero de
    // entrada para que el tour siempre encuentre sus pasos).
    // Lista perezosa (ListView.builder): cada tarjeta del historial se crea
    // recién cuando aparece en pantalla, no las ~200 de una vez al entrar. El
    // encabezado es el ítem 0 y se construye entero, así el tour siempre
    // encuentra sus pasos.
    final lista = svc.historialFiltrado;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 1 + (lista.isEmpty ? 1 : lista.length),
      itemBuilder: (context, i) {
        if (i == 0) {
          // Encabezado + buscador (texto, Desde/Hasta, PDF y Excel de lo filtrado).
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _encabezado(context, svc),
            BarraFiltros(
              filtro: svc.filtro,
              onCambio: svc.filtrar,
              reporte: svc.reporte,
              hint: 'Buscar por sabor, presentación, lote, responsable…',
            ),
            const SizedBox(height: 12),
          ]);
        }
        if (lista.isEmpty) {
          if (svc.filtro.activo) return const SinResultados();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay corridas finalizadas.',
                style: TextStyle(color: Colors.black54)),
          );
        }
        final c = lista[i - 1];
        return _TarjetaCorrida(svc: svc, c: c);
      },
    );
  }

  Widget _encabezado(BuildContext context, SopladoService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Soplado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'soplado', pasos: _pasosAyuda),
          ],
        ),
        if (svc.puedeCrear) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _pasoIniciar.envolver(
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _iniciar(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Iniciar corrida'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _pasoAvance.envolver(_SeccionAvance(svc: svc)),
        const SizedBox(height: 20),
        if (svc.enCurso.isNotEmpty) ...[
          const Text('En curso', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          for (final c in svc.enCurso) _TarjetaCorrida(svc: svc, c: c),
          const SizedBox(height: 20),
        ],
        _pasoHistorial.envolver(
          const Text('Historial',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SeccionAvance extends StatelessWidget {
  final SopladoService svc;
  const _SeccionAvance({required this.svc});

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
          const Text('Avance de los últimos 14 días',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (svc.avance.isEmpty)
            const Text('Sin corridas finalizadas en este período.',
                style: TextStyle(color: Colors.black54))
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final a in svc.avance)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${a.sabor} · ${a.presentacion}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                            '${fmtNum(a.botellasBuenas, decimales: 0)} botellas'
                            '${a.cajasSopladas == null ? '' : ' (${fmtNum(a.cajasSopladas, decimales: 1)} cajas)'}'
                            ' · ${a.corridas} corrida${a.corridas == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TarjetaCorrida extends StatelessWidget {
  final SopladoService svc;
  final CorridaSoplado c;
  const _TarjetaCorrida({required this.svc, required this.c});

  Color _color() {
    switch (c.estado) {
      case EstadoCorrida.enCurso:
        return const Color(0xFFD97706);
      case EstadoCorrida.finalizada:
        return const Color(0xFF16A34A);
      case EstadoCorrida.anulada:
        return Colors.black45;
    }
  }

  Future<void> _finalizar(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => FinalizarCorridaDialog(servicio: svc, corrida: c),
      );

  Future<void> _anular(BuildContext context) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Anular corrida'),
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
    final error = await svc.anularCorrida(c, motivo);
    if (!context.mounted) return;
    error == null
        ? mostrarExito(context, 'Corrida anulada.')
        : mostrarError(context, error);
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
                  child: Text('${c.sabor ?? ''} · ${c.presentacion ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (c.sinSubir) const ChipSinSubir(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _color().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(c.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: _color())),
                ),
              ],
            ),
            Text(
              c.horaFin == null
                  ? 'Inicio: ${fmtFechaHora(c.horaInicio)} · ${c.responsableNombre ?? '—'}'
                  : 'Inicio: ${fmtFechaHora(c.horaInicio)} · Fin: ${fmtFechaHora(c.horaFin)} '
                      '(${c.duracion!.inMinutes} min) · ${c.responsableNombre ?? '—'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (c.lotePreforma != null || c.proveedorNombre != null)
              Text(
                [
                  if (c.proveedorNombre != null) c.proveedorNombre!,
                  if (c.lotePreforma != null) 'Lote ${c.lotePreforma}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (c.estado == EstadoCorrida.finalizada) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _pill('${fmtNum(c.botellasSopladas, decimales: 0)} sopladas', AppColors.primario),
                if (c.botellasEtiquetadas != null)
                  _pill('${fmtNum(c.botellasEtiquetadas, decimales: 0)} etiquetadas', AppColors.negro),
                if (c.tieneMerma)
                  _pill('Merma: ${c.mermaPreforma + c.mermaSoplado + c.mermaEtiquetado}',
                      const Color(0xFFDC2626)),
                if ((c.tiempoParadaMinutos ?? 0) > 0)
                  _pill('Parada: ${c.tiempoParadaMinutos} min', const Color(0xFFD97706)),
              ]),
              if (c.motivoMerma != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Motivo de la merma: ${c.motivoMerma}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              if (c.motivoParada != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Motivo de la parada: ${c.motivoParada}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
            ],
            if (c.observaciones != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(c.observaciones!),
              ),
            if (c.estado == EstadoCorrida.enCurso && svc.puedeEditar) ...[
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
