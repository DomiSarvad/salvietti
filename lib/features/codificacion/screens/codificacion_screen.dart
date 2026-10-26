import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../presencia/widgets/aviso_conexion_areas.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/codificacion_modelos.dart';
import '../repositories/codificacion_repository.dart';
import '../services/codificacion_service.dart';
import '../widgets/finalizar_corrida_dialog.dart';
import '../widgets/iniciar_corrida_dialog.dart';
import '../../../shared/chip_sin_subir.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Producción de Codificación: corridas en curso, historial y el avance de
/// los últimos 14 días. Solo UI; las reglas viven en el service.
class CodificacionScreen extends StatelessWidget {
  const CodificacionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => CodificacionService(SupabaseCodificacionRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<CodificacionService>().recargar(),
        child: const _Vista(),
      ),
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
    texto: 'Se vincula a una corrida de Llenadora.',
  );
  final _pasoAvance = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Avance de los últimos 14 días',
    texto: 'Lo codificado en las últimas dos semanas.',
  );
  final _pasoHistorial = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Historial',
    texto: 'Corridas cerradas. Solo registra consumo, no descuenta stock.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context,
            idTour: 'codificacion', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoIniciar, _pasoAvance, _pasoHistorial];

  Future<void> _iniciar(BuildContext context, CodificacionService svc) => showDialog<bool>(
        context: context,
        builder: (_) => IniciarCorridaDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CodificacionService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Codificación.'),
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
              hint: 'Buscar por sabor, lote, código impreso, responsable…',
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

  Widget _encabezado(BuildContext context, CodificacionService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Codificación',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'codificacion', pasos: _pasosAyuda),
          ],
        ),
        // Codificación sigue las corridas de Llenadora: si Llenadora está sin internet, avisa.
        const AvisoConexionAreas(roles: [Rol.llenadora], margen: EdgeInsets.only(top: 10)),
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
  final CodificacionService svc;
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
                            '${fmtNum(a.botellasBuenas, decimales: 0)} botellas · '
                            '${a.corridas} corrida${a.corridas == 1 ? '' : 's'}',
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
  final CodificacionService svc;
  final CorridaCodificacion c;
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
                  ? 'Turno ${c.turno.etiqueta} · Inicio: ${fmtFechaHora(c.horaInicio)} · ${c.responsableNombre ?? '—'}'
                  : 'Turno ${c.turno.etiqueta} · Inicio: ${fmtFechaHora(c.horaInicio)} · Fin: ${fmtFechaHora(c.horaFin)} '
                      '(${c.duracion!.inMinutes} min) · ${c.responsableNombre ?? '—'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (c.nLote != null)
              Text('Lote ${c.nLote}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (c.estado == EstadoCorrida.finalizada) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _pill('${fmtNum(c.botellasCodificadas, decimales: 0)} codificadas', AppColors.primario),
                if (c.codigoImpreso != null) _pill(c.codigoImpreso!, AppColors.negro),
                if (c.tieneMerma)
                  _pill('Merma: ${fmtNum(c.botellasMalTapadas + c.tapasMalTapadas + c.impurezas, decimales: 0)}',
                      const Color(0xFFDC2626)),
              ]),
              if (c.motivoMerma != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Motivo de la merma: ${c.motivoMerma}',
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
