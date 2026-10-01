import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../models/informe_modelos.dart';
import '../repositories/informe_repository.dart';
import '../services/informe_service.dart';

/// Informe general de Producción: un resumen por sabor y día, comparando
/// lo esperado (Jarabes × estándar del sabor) contra lo producido
/// (Registro de salidas), con el detalle de merma por área al hacer clic.
/// Todo sale de vistas de solo lectura; nada se escribe desde acá.
class InformeScreen extends StatelessWidget {
  const InformeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => InformeService(SupabaseInformeRepository(), usuario)..iniciar(),
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
  final _pasoInfo = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Esperado vs. producido',
    texto: 'Compara lo esperado según el estándar de cada sabor contra lo producido. '
        'Tocá una fila para ver la merma por área ese día. Es de solo lectura: nada se '
        'carga desde acá.',
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

    // El resumen puede crecer mucho: queda como lista perezosa aparte,
    // después del encabezado (que se construye entero de entrada para que
    // el tour siempre encuentre sus pasos).
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Informe general de Producción',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'informe_produccion', pasos: _pasosAyuda),
          ],
        ),
        const SizedBox(height: 4),
        _pasoInfo.envolver(
          const Text(
              'Compara lo esperado según el estándar de cada sabor contra lo producido. '
              'Tocá una fila para ver la merma por área ese día.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        const SizedBox(height: 16),
        if (svc.resumen.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('Todavía no hay datos para mostrar.',
                    style: TextStyle(color: Colors.black54))),
          )
        else
          for (final r in svc.resumen) _TarjetaResumen(svc: svc, r: r),
      ],
    );
  }
}

class _TarjetaResumen extends StatefulWidget {
  final InformeService svc;
  final ResumenProduccion r;
  const _TarjetaResumen({required this.svc, required this.r});

  @override
  State<_TarjetaResumen> createState() => _TarjetaResumenState();
}

class _TarjetaResumenState extends State<_TarjetaResumen> {
  bool _abierto = false;
  Future<List<DetalleMermaArea>>? _detalle;

  void _alternar() {
    setState(() {
      _abierto = !_abierto;
      if (_abierto) _detalle ??= widget.svc.mermaDe(widget.r);
    });
  }

  Color _colorDesviacion(ResumenProduccion r) {
    if (r.desviacionPorcentaje == null) return Colors.black54;
    return r.alertaDesviacion ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: r.alertaDesviacion ? const BorderSide(color: Color(0xFFDC2626)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _alternar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${r.sabor} · ${fmtFecha(r.fecha)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Icon(_abierto ? Icons.expand_less : Icons.expand_more, color: Colors.black38),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (r.preparados != null)
                  _pill('${fmtNum(r.preparados, decimales: 1)} preparados', Colors.black54),
                if (r.cajasEsperadas != null)
                  _pill('Esperado: ${fmtNum(r.cajasEsperadas, decimales: 1)} cajas', Colors.black54),
                if (r.cajasProducidas != null)
                  _pill('Producido: ${fmtNum(r.cajasProducidas, decimales: 1)} cajas', AppColors.primario),
                if (r.desviacionPorcentaje != null)
                  _pill('Desviación: ${r.desviacionPorcentaje! > 0 ? '+' : ''}'
                          '${fmtNum(r.desviacionPorcentaje, decimales: 1)} %',
                      _colorDesviacion(r)),
                if (r.datosIncompletos)
                  _pill('Datos incompletos', const Color(0xFFD97706)),
              ]),
              if (_abierto) ...[
                const Divider(height: 20),
                FutureBuilder<List<DetalleMermaArea>>(
                  future: _detalle,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final eventos = snap.data ?? const [];
                    if (eventos.isEmpty) {
                      return const Text('Sin merma registrada este día para este sabor.',
                          style: TextStyle(fontSize: 12, color: Colors.black54));
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Merma por área', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        for (final e in eventos)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Expanded(child: Text(_etiquetaArea(e.area))),
                              Text(
                                '${fmtNum(e.totalMerma, decimales: 0)}'
                                '${e.porcentaje == null ? '' : ' (${fmtNum(e.porcentaje, decimales: 1)} %)'}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: e.alerta ? const Color(0xFFDC2626) : Colors.black87),
                              ),
                            ]),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _etiquetaArea(String area) => switch (area) {
        'soplado' => 'Soplado',
        'llenadora' => 'Llenadora',
        'codificacion' => 'Codificación',
        'jarabes' => 'Jarabes',
        'calidad' => 'Calidad',
        'vidrio' => 'Vidrio',
        _ => area,
      };

  Widget _pill(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}
