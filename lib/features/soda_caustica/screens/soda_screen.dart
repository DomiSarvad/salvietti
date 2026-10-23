import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../shared/ayuda/tour_ayuda.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/soda_modelos.dart';
import '../repositories/soda_repository.dart';
import '../services/soda_pdf_service.dart';
import '../services/soda_service.dart';
import '../widgets/registrar_entrega_dialog.dart';

/// Soda Cáustica: historial de entregas, con su constancia en PDF (producto
/// peligroso). El stock se ve en Almacenes, como el de cualquier otro
/// almacén; acá solo se registra a quién se le entregó. Solo UI; las
/// reglas viven en el service.
class SodaScreen extends StatelessWidget {
  const SodaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => SodaService(SupabaseSodaRepository(), usuario)..iniciar(),
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
    titulo: 'Stock vs. entregas',
    texto: 'El stock que llega de Almacén se ve en "Almacenes", como el de cualquier '
        'otro almacén. Acá solo se registra a quién se le entrega, para la constancia.',
  );
  final _pasoRegistrar = PasoAyuda(
    clave: GlobalKey(),
    titulo: 'Registrar entrega',
    texto: 'Por ser un producto peligroso, cada entrega genera una constancia en PDF.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        TourAyuda.mostrar(context, idTour: 'soda_caustica', soloSiNoVisto: true, pasos: _pasosAyuda());
      }
    });
  }

  List<PasoAyuda> _pasosAyuda() => [_pasoInfo, _pasoRegistrar];

  Future<void> _registrar(BuildContext context, SodaService svc) => showDialog<bool>(
        context: context,
        builder: (_) => RegistrarEntregaDialog(servicio: svc),
      );

  Future<void> _pdf(BuildContext context, EntregaSoda e) async {
    try {
      final bytes = await SodaPdfService.pdf(e);
      final mensaje = await SodaPdfService.guardar(bytes, e);
      if (context.mounted) mostrarExito(context, mensaje);
    } catch (_) {
      if (context.mounted) mostrarError(context, 'No se pudo generar el PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SodaService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Soda Cáustica.'),
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

    // El historial de entregas puede crecer mucho: queda como lista
    // perezosa aparte, después del encabezado (que se construye entero de
    // entrada para que el tour siempre encuentre sus pasos).
    // Lista perezosa (ListView.builder): cada tarjeta del historial se crea
    // recién cuando aparece en pantalla, no las ~200 de una vez al entrar. El
    // encabezado es el ítem 0 y se construye entero, así el tour siempre
    // encuentra sus pasos.
    final lista = svc.entregas;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 1 + (lista.isEmpty ? 1 : lista.length),
      itemBuilder: (context, i) {
        if (i == 0) return _encabezado(context, svc);
        if (lista.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('Todavía no hay entregas registradas.',
                    style: TextStyle(color: Colors.black54))),
          );
        }
        final e = lista[i - 1];
        return _TarjetaEntrega(e: e, onPdf: () => _pdf(context, e));
      },
    );
  }

  Widget _encabezado(BuildContext context, SodaService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Soda Cáustica',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BotonAyuda(idTour: 'soda_caustica', pasos: _pasosAyuda),
          ],
        ),
        if (svc.puedeCrear) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _pasoRegistrar.envolver(
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _registrar(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Registrar entrega'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _pasoInfo.envolver(
          const Text(
              'El stock (lo que llega de Almacén) se ve en "Almacenes"; acá se registra a quién '
              'se le entrega, para la constancia.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TarjetaEntrega extends StatelessWidget {
  final EntregaSoda e;
  final VoidCallback onPdf;
  const _TarjetaEntrega({required this.e, required this.onPdf});

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
                  child: Text('${e.detalle} · ${fmtNum(e.cantidad)} ${e.unidad}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                IconButton(
                  tooltip: 'Constancia en PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626)),
                  onPressed: onPdf,
                ),
              ],
            ),
            Text(
              'Entregado a ${e.entregadoA}'
              '${e.areaRecibe == null ? '' : ' · ${e.areaRecibe}'}'
              ' · ${fmtFechaHora(e.fechaHora)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (e.motivo != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(e.motivo!, style: const TextStyle(fontSize: 13)),
              ),
            if (e.saldoRestante != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Saldo restante: ${fmtNum(e.saldoRestante)} ${e.unidad}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Entregó: ${e.responsableNombre ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: Colors.black38)),
            ),
          ],
        ),
      ),
    );
  }
}
