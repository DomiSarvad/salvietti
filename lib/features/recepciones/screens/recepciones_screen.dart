import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../models/recepciones_modelos.dart';
import '../repositories/recepciones_repository.dart';
import '../services/recepciones_service.dart';
import '../widgets/recepcion_detalle_dialog.dart';
import '../widgets/recepcion_form_dialog.dart';
import '../../../shared/filtros/barra_filtros.dart';

/// Recepciones de Almacén: lista de lo que llegó (factura contra peso real) y
/// reclamos del mes por diferencia. Solo UI; las reglas están en el service.
class RecepcionesScreen extends StatelessWidget {
  const RecepcionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          RecepcionesService(SupabaseRecepcionesRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<RecepcionesService>().recargar(),
        child: const _Vista(),
      ),
    );
  }
}

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  final _pasoAlmacenChips = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Almacenes',
    texto: 'Elegí con qué almacén trabajar.',
  );
  final _pasoVista = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Recepciones / Reclamos del mes',
    texto: 'Lo que llegó, y lo que faltó por proveedor.',
  );
  final _pasoBuscador = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Buscador y filtro',
    texto: '"Con diferencia": donde lo real no coincide con la factura.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context,
            idTour: 'recepciones', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoAlmacenChips, _pasoVista, _pasoBuscador];

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<RecepcionesService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (svc.error != null && svc.almacenes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(svc.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    if (svc.almacenes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a las recepciones de ningún almacén.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Cabecera(
          svc: svc,
          pasoAlmacenChips: _pasoAlmacenChips,
          pasoVista: _pasoVista,
          pasoBuscador: _pasoBuscador,
          pasosAyuda: _pasosAyuda,
        ),
        Expanded(
          child: svc.vista == VistaRecepciones.lista
              ? _Lista(svc: svc)
              : _Reclamos(svc: svc),
        ),
      ],
    );
  }
}

class _Cabecera extends StatelessWidget {
  final RecepcionesService svc;
  final PasoAyuda pasoAlmacenChips;
  final PasoAyuda pasoVista;
  final PasoAyuda pasoBuscador;
  final List<PasoAyuda> Function() pasosAyuda;
  const _Cabecera({
    required this.svc,
    required this.pasoAlmacenChips,
    required this.pasoVista,
    required this.pasoBuscador,
    required this.pasosAyuda,
  });

  Future<void> _nueva(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (_) => RecepcionFormDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Recepciones',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              BotonAyuda(idTour: 'recepciones', pasos: pasosAyuda),
            ],
          ),
          if (svc.puedeRecibirEn(svc.almacenId ?? '') ||
              svc.almacenes.any((a) => svc.puedeRecibirEn(a.id))) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _nueva(context),
                icon: const Icon(Icons.add),
                label: const Text('Nueva recepción'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          pasoAlmacenChips.envolver(
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in svc.almacenes)
                  ChoiceChip(
                    label: Text(a.nombre),
                    selected: a.id == svc.almacenId,
                    selectedColor: AppColors.primario,
                    labelStyle: TextStyle(
                        color: a.id == svc.almacenId ? Colors.white : Colors.black87),
                    onSelected: (_) => svc.seleccionarAlmacen(a.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          pasoVista.envolver(SegmentedButton<VistaRecepciones>(
            segments: const [
              ButtonSegment(
                  value: VistaRecepciones.lista,
                  icon: Icon(Icons.list_alt),
                  label: Text('Recepciones')),
              ButtonSegment(
                  value: VistaRecepciones.reclamos,
                  icon: Icon(Icons.report_gmailerrorred_outlined),
                  label: Text('Reclamos del mes')),
            ],
            selected: {svc.vista},
            onSelectionChanged: (s) => svc.cambiarVista(s.first),
          )),
          if (svc.vista == VistaRecepciones.lista) ...[
            const SizedBox(height: 10),
            // Buscador común: texto, Desde/Hasta, y PDF/Excel de lo filtrado.
            pasoBuscador.envolver(Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BarraFiltros(
                  filtro: svc.filtro,
                  onCambio: svc.filtrar,
                  reporte: svc.reporte,
                  hint: 'Buscar por ítem, proveedor, factura o lote…',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Con diferencia'),
                    selected: svc.soloConDiferencia,
                    onSelected: (_) => svc.alternarSoloConDiferencia(),
                  ),
                ),
              ],
            )),
          ],
        ],
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  final RecepcionesService svc;
  const _Lista({required this.svc});

  @override
  Widget build(BuildContext context) {
    final items = svc.visibles;
    if (items.isEmpty) {
      return const Center(
          child: Text('No hay recepciones para mostrar.',
              style: TextStyle(color: Colors.black54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _Tarjeta(svc: svc, r: items[i]),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final RecepcionesService svc;
  final RecepcionDetalle r;
  const _Tarjeta({required this.svc, required this.r});

  Widget _pill(String texto, Color color, {IconData? icono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 4)],
          Text(texto, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final sinDif = r.diferencia.abs() < 1e-9;
    final vence = r.fechaVencimiento;
    final diasParaVencer = vence?.difference(DateTime.now()).inDays;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => RecepcionDetalleDialog(servicio: svc, r: r),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.detalle,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text(fmtFecha(r.fecha),
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
              Text(
                [
                  r.proveedor ?? 'Sin proveedor',
                  if (r.nFactura != null) 'Factura ${r.nFactura}',
                  if (r.nLote != null) 'Lote ${r.nLote}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _pill('Factura: ${fmtNum(r.cantidadFactura, decimales: 3)} ${r.unidad}',
                      AppColors.negro),
                  _pill('Real: ${fmtNum(r.cantidadReal, decimales: 3)} ${r.unidad}',
                      AppColors.primario),
                  if (!sinDif)
                    _pill(
                      '${r.diferencia > 0 ? '+' : ''}${fmtNum(r.diferencia, decimales: 3)} ${r.unidad}',
                      r.diferencia < 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                      icono: Icons.balance,
                    ),
                  if (diasParaVencer != null && diasParaVencer <= 90)
                    _pill(
                      diasParaVencer < 0 ? 'Vencido' : 'Vence en $diasParaVencer días',
                      diasParaVencer < 30 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                      icono: Icons.event_busy_outlined,
                    ),
                  if (r.fotoUrl != null)
                    _pill('Con foto', Colors.black54, icono: Icons.photo_outlined),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reclamos del mes: lo que faltó por proveedor e ítem.
class _Reclamos extends StatelessWidget {
  final RecepcionesService svc;
  const _Reclamos({required this.svc});

  @override
  Widget build(BuildContext context) {
    final mes = svc.mesReclamos;
    final faltantes = svc.reclamosConFaltante;
    final hoy = DateTime.now();
    final esMesActual = mes.year == hoy.year && mes.month == hoy.month;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => svc.cargarReclamos(DateTime(mes.year, mes.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_meses[mes.month - 1]} ${mes.year}'.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
              IconButton(
                onPressed: esMesActual
                    ? null
                    : () => svc.cargarReclamos(DateTime(mes.year, mes.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: faltantes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No hay faltantes registrados este mes.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: faltantes.length,
                  itemBuilder: (_, i) {
                    final d = faltantes[i];
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(d.detalle,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${d.proveedor ?? 'Sin proveedor'} · ${d.recepciones} '
                            'recepci${d.recepciones == 1 ? 'ón' : 'ones'} · '
                            'facturado ${fmtNum(d.cantidadFactura, decimales: 3)} ${d.unidad}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${fmtNum(d.diferencia, decimales: 3)} ${d.unidad}',
                                style: const TextStyle(
                                    color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
                            if (d.porcentaje != null)
                              Text('${fmtNum(d.porcentaje, decimales: 2)} %',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
