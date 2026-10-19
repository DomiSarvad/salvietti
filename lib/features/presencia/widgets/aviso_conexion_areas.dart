import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../models/presencia.dart';
import '../services/presencia_service.dart';

/// Aviso para poner junto a datos que vienen de OTRA área: si alguien de
/// [roles] está sin señal (o tiene registros sin subir), lo dice, para no
/// tomar una decisión con un dato que puede estar atrasado. Si todo está
/// bien no ocupa lugar.
///
/// Ej.: en Jarabes, junto al avance de Soplado →
/// "Soplado (Juan Pérez): sin señal desde las 10:32. Lo que registró desde
///  entonces todavía no está acá: confirmá con Soplado antes de decidir."
class AvisoConexionAreas extends StatelessWidget {
  final List<String> roles;
  final EdgeInsetsGeometry margen;

  const AvisoConexionAreas({
    super.key,
    required this.roles,
    this.margen = const EdgeInsets.only(bottom: 10),
  });

  static String _area(String rol) => Rol.area(rol).replaceFirst('Producción · ', '');

  static String _hora(DateTime d) {
    final hoy = DateTime.now();
    final mismoDia = d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
    final hhmm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return mismoDia ? 'las $hhmm' : '${fmtFecha(d)} $hhmm';
  }

  @override
  Widget build(BuildContext context) {
    final avisos = context.watch<PresenciaService>().avisosDe(roles);
    if (avisos.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: margen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final a in avisos) _aviso(a)],
      ),
    );
  }

  Widget _aviso(AvisoArea a) {
    final quien = '${_area(a.rol)}${a.nombre.isEmpty ? '' : ' (${a.nombre})'}';
    final sinSenal = a.tipo == TipoAvisoArea.sinSenal;
    final texto = sinSenal
        ? '$quien: sin señal desde ${_hora(a.ultimaSenal)} (sin internet, o cerró la app). '
            'Si sigue trabajando, lo que registró desde entonces todavía no se ve acá: '
            'confirmá con esa área antes de decidir con estos datos.'
        : '$quien: tiene ${a.pendientes} registro${a.pendientes == 1 ? '' : 's'} hecho'
            '${a.pendientes == 1 ? '' : 's'} sin internet que se ${a.pendientes == 1 ? 'está' : 'están'} '
            'subiendo. Estos datos pueden cambiar en un momento.';
    const color = Color(0xFFD97706);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(sinSenal ? Icons.wifi_off : Icons.cloud_upload_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}
