import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/recargar_al_reconectar.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../shared/filtros/barra_filtros.dart';
import '../../../utils/formatters.dart';
import '../models/informe_modelos.dart';
import '../repositories/informe_repository.dart';
import '../services/informe_service.dart';

/// Informe general de Producción: por sabor y día, lo esperado (Jarabes ×
/// estándar del sabor) contra lo producido (Registro de salidas). Arriba los
/// totales de lo que se ve, el buscador y "Solo con desvío"; la lista va del
/// día más reciente al más antiguo, y tocar una fila abre su detalle (con la
/// merma por área). Todo sale de vistas de solo lectura.
class InformeScreen extends StatelessWidget {
  const InformeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => InformeService(SupabaseInformeRepository(), usuario)..iniciar(),
      child: RecargarAlReconectar(
        alReconectar: (c) => c.read<InformeService>().recargar(),
        child: const _Vista(),
      ),
    );
  }
}

const _rojo = Color(0xFFDC2626);
const _verde = Color(0xFF16A34A);
const _ambar = Color(0xFFD97706);

Color _colorDesviacion(double? d) =>
    d == null ? Colors.black54 : (d.abs() > 3 ? _rojo : _verde);

String _desviacionTexto(double? d) =>
    d == null ? '—' : '${d > 0 ? '+' : ''}${fmtNum(d, decimales: 1)} %';

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> {
  // Solo sobre el resumen de arriba: si envolvía toda la lista, mantener
  // apretada cualquier fila mostraba este globo encima de los datos.
  final _pasoInfo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Esperado vs. producido',
    texto: 'Tocá un sabor para ver su detalle.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'informe_produccion', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoInfo];

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<InformeService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso al Informe general de Producción.'),
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

    final dias = svc.porDia;
    // Encabezado entero como ítem 0 (para el tour); los días, perezosos.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 1 + (dias.isEmpty ? 1 : dias.length),
      itemBuilder: (context, i) {
        if (i == 0) return _encabezado(svc);
        if (dias.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: svc.hayFiltros
                ? const SinResultados()
                : const Center(
                    child: Text('Todavía no hay datos para mostrar.',
                        style: TextStyle(color: Colors.black54))),
          );
        }
        final (dia, filas) = dias[i - 1];
        return _Dia(svc: svc, dia: dia, filas: filas);
      },
    );
  }

  Widget _encabezado(InformeService svc) {
    final t = svc.totales;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(
          child: Text('Informe general de Producción',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        BotonAyuda(idTour: 'informe_produccion', pasos: _pasosAyuda),
      ]),
      const SizedBox(height: 6),
      Text(
        t.dias == 0
            ? 'Sin días con esperado y producido para sumar.'
            : 'Suma de ${t.dias} día${t.dias == 1 ? '' : 's'} con esperado y producido'
                '${t.desde == t.hasta ? ' (${fmtFecha(t.desde)})' : ' (${fmtFecha(t.desde)} – ${fmtFecha(t.hasta)})'}',
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      const SizedBox(height: 8),
      _pasoInfo.envolver(Wrap(spacing: 10, runSpacing: 10, children: [
        _Kpi(etiqueta: 'Cajas esperadas', valor: fmtNum(t.esperadas, decimales: 0)),
        _Kpi(etiqueta: 'Cajas producidas', valor: fmtNum(t.producidas, decimales: 0)),
        _Kpi(
            etiqueta: 'Desviación',
            valor: _desviacionTexto(t.desviacion),
            color: _colorDesviacion(t.desviacion)),
        _Kpi(
            etiqueta: 'Con desvío (> 3 %)',
            valor: '${t.conDesvio}',
            color: t.conDesvio > 0 ? _rojo : null),
      ])),
      const SizedBox(height: 12),
      BarraFiltros(filtro: svc.filtro, onCambio: svc.filtrar, hint: 'Buscar sabor…'),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          avatar: const Icon(Icons.warning_amber_rounded, size: 18),
          label: Text('Solo con desvío${t.conDesvio > 0 && !svc.soloDesvio ? ' (${t.conDesvio})' : ''}'),
          selected: svc.soloDesvio,
          onSelected: (_) => svc.alternarSoloDesvio(),
        ),
      ),
      const SizedBox(height: 4),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color? color;
  const _Kpi({required this.etiqueta, required this.valor, this.color});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? Colors.black87)),
        ]),
      );
}

/// Un día: su fecha como título y una fila por sabor.
class _Dia extends StatelessWidget {
  final InformeService svc;
  final DateTime dia;
  final List<ResumenProduccion> filas;
  const _Dia({required this.svc, required this.dia, required this.filas});

  String get _titulo {
    final hoy = DateTime.now();
    final h = DateTime(hoy.year, hoy.month, hoy.day);
    if (dia == h) return 'Hoy';
    if (dia == h.subtract(const Duration(days: 1))) return 'Ayer';
    return fmtFecha(dia);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(_titulo,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)),
          ),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE3E7EB)),
            ),
            child: Column(children: [
              for (var i = 0; i < filas.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                _Fila(svc: svc, r: filas[i]),
              ],
            ]),
          ),
        ]),
      );
}

/// Un sabor de un día: barra de avance (producido sobre esperado) y la
/// desviación a la derecha. Tocar abre el detalle.
class _Fila extends StatelessWidget {
  final InformeService svc;
  final ResumenProduccion r;
  const _Fila({required this.svc, required this.r});

  @override
  Widget build(BuildContext context) {
    final avance = (r.cajasEsperadas ?? 0) <= 0
        ? null
        : ((r.cajasProducidas ?? 0) / r.cajasEsperadas!).clamp(0.0, 1.0);
    final color = _colorDesviacion(r.desviacionPorcentaje);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _Detalle(svc: svc, r: r),
      )),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: r.datosIncompletos ? _ambar : color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.sabor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${fmtNum(r.cajasProducidas ?? 0, decimales: 1)} de '
                '${r.cajasEsperadas == null ? '—' : fmtNum(r.cajasEsperadas, decimales: 1)} cajas'
                '${r.datosIncompletos ? ' · datos incompletos' : ''}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              if (avance != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: avance,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE8ECEF),
                    color: AppColors.primario,
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Text(_desviacionTexto(r.desviacionPorcentaje),
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const Icon(Icons.chevron_right, color: Colors.black38),
        ]),
      ),
    );
  }
}

/// Detalle de un sabor en un día, a pantalla completa: los números grandes,
/// qué significa la desviación y la merma de cada área.
class _Detalle extends StatefulWidget {
  final InformeService svc;
  final ResumenProduccion r;
  const _Detalle({required this.svc, required this.r});

  @override
  State<_Detalle> createState() => _DetalleState();
}

class _DetalleState extends State<_Detalle> {
  late final Future<List<DetalleMermaArea>> _merma = widget.svc.mermaDe(widget.r);

  static String _area(String area) => switch (area) {
        'soplado' => 'Soplado',
        'llenadora' => 'Llenadora',
        'codificacion' => 'Codificación',
        'jarabes' => 'Jarabes',
        'calidad' => 'Calidad',
        'vidrio' => 'Vidrio',
        _ => area,
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final d = r.desviacionPorcentaje;
    final color = _colorDesviacion(d);
    final explicacion = d == null
        ? 'Falta lo esperado o lo producido para comparar.'
        : d.abs() <= 3
            ? 'Dentro de lo normal (hasta 3 % de diferencia).'
            : d > 0
                ? 'Se produjo más de lo esperado: revisar el estándar del sabor o lo cargado.'
                : 'Se produjo menos de lo esperado: mirar la merma de cada área.';

    return Scaffold(
      backgroundColor: AppColors.fondo,
      // Barra negra como la de la app, para no perder la identidad visual.
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        surfaceTintColor: AppColors.negro,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.sabor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(fmtFecha(r.fecha), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Desviación, grande.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Desviación', style: TextStyle(fontSize: 12, color: Colors.black54)),
            Text(_desviacionTexto(d),
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: color)),
            if (r.desviacionCajas != null)
              Text('${r.desviacionCajas! > 0 ? '+' : ''}${fmtNum(r.desviacionCajas, decimales: 1)} cajas',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 6),
            Text(explicacion, style: const TextStyle(fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (r.preparados != null)
            _Kpi(etiqueta: 'Preparados de Jarabes', valor: fmtNum(r.preparados, decimales: 1)),
          _Kpi(
              etiqueta: 'Cajas esperadas',
              valor: r.cajasEsperadas == null ? '—' : fmtNum(r.cajasEsperadas, decimales: 1)),
          _Kpi(
              etiqueta: 'Cajas producidas',
              valor: r.cajasProducidas == null ? 'Sin cargar' : fmtNum(r.cajasProducidas, decimales: 1),
              color: AppColors.primario),
        ]),
        if (r.datosIncompletos) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _ambar.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: _ambar, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Datos incompletos: falta cargar el preparado de Jarabes o el '
                    'registro de salidas de este día.'),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
        const Text('Merma por área', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        FutureBuilder<List<DetalleMermaArea>>(
          future: _merma,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (snap.hasError) {
              return Text(
                  snap.error is ErrorInforme
                      ? (snap.error as ErrorInforme).mensaje
                      : 'No se pudo cargar la merma. Revisá la conexión.',
                  style: const TextStyle(color: Colors.black54));
            }
            final eventos = snap.data ?? const [];
            if (eventos.isEmpty) {
              return const Text('Sin merma registrada este día para este sabor.',
                  style: TextStyle(color: Colors.black54));
            }
            final maximo = eventos.fold<double>(0, (m, e) => e.totalMerma > m ? e.totalMerma : m);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3E7EB)),
              ),
              child: Column(children: [
                for (final e in eventos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                            child: Text(_area(e.area),
                                style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(
                          '${fmtNum(e.totalMerma, decimales: 0)}'
                          '${e.porcentaje == null ? '' : ' · ${fmtNum(e.porcentaje, decimales: 1)} %'}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: e.alerta ? _rojo : Colors.black87),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maximo <= 0 ? 0 : e.totalMerma / maximo,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE8ECEF),
                          color: e.alerta ? _rojo : AppColors.secundario,
                        ),
                      ),
                      if (e.motivo != null && e.motivo!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(e.motivo!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ]),
                  ),
              ]),
            );
          },
        ),
      ]),
    );
  }
}
