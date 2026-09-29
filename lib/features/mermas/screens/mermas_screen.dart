import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';
import '../models/mermas_modelos.dart';
import '../repositories/mermas_repository.dart';
import '../services/mermas_service.dart';
import '../widgets/registrar_merma_dialog.dart';

/// Mermas: consolida en un solo lugar la de Soplado, Llenadora y
/// Codificación (que ya se registra dentro de sus corridas) con la que se
/// carga acá para Jarabes, Calidad y Vidrio. Se marca en rojo lo que supera
/// el 3 % de lo producido. Solo UI; las reglas viven en el service.
class MermasScreen extends StatelessWidget {
  const MermasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => MermasService(SupabaseMermasRepository(), usuario)..iniciar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatelessWidget {
  const _Vista();

  Future<void> _registrar(BuildContext context, MermasService svc) => showDialog<bool>(
        context: context,
        builder: (_) => RegistrarMermaDialog(servicio: svc),
      );

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MermasService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Tu rol no tiene acceso a Mermas.'),
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

    final puedeCrear = svc.puedeCrear && svc.areasPermitidas.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Mermas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (puedeCrear)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                onPressed: () => _registrar(context, svc),
                icon: const Icon(Icons.add),
                label: const Text('Registrar merma'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
            'Soplado, Llenadora y Codificación ya quedan acá solas (se registran en su propia '
            'corrida). Jarabes, Calidad y Vidrio se cargan con el botón de arriba.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 16),
        if (svc.conAlerta.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${svc.conAlerta.length} evento${svc.conAlerta.length == 1 ? '' : 's'} '
                  'por encima del 3 % de merma.',
                  style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        if (svc.consolidado.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: Text('Todavía no hay eventos de merma registrados.',
                    style: TextStyle(color: Colors.black54))),
          )
        else
          for (final e in svc.consolidado) _TarjetaEvento(e: e),
      ],
    );
  }
}

class _TarjetaEvento extends StatelessWidget {
  final EventoMerma e;
  const _TarjetaEvento({required this.e});

  String _etiquetaArea(String area) => switch (area) {
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
    final color = e.alerta ? const Color(0xFFDC2626) : AppColors.primario;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: e.alerta ? const BorderSide(color: Color(0xFFDC2626)) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${_etiquetaArea(e.area)} · ${e.sabor}${e.presentacion == null ? '' : ' · ${e.presentacion}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(fmtFecha(e.fecha), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _pill('Merma: ${fmtNum(e.totalMerma, decimales: 0)}', color),
              if (e.producido != null)
                _pill('Producido: ${fmtNum(e.producido, decimales: 0)}', Colors.black54),
              if (e.porcentaje != null)
                _pill('${fmtNum(e.porcentaje, decimales: 1)} %', color),
              if (e.alerta) _pill('Supera el 3 %', const Color(0xFFDC2626)),
            ]),
            if (e.motivo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Motivo: ${e.motivo}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
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
