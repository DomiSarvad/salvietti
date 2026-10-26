import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../models/solicitud.dart';
import '../services/solicitud_pdf_service.dart';
import '../services/solicitudes_service.dart';

/// Una solicitud vista como conversación: el pedido del área es el primer
/// mensaje y la respuesta de Gerencia, la contestación. Lo propio va a la
/// derecha (como en cualquier chat). Si está pendiente y quien mira puede
/// aprobar, abajo está la caja para responder con Aprobar/Rechazar
/// (reemplaza al diálogo de antes). Es solo el aspecto: sigue siendo un
/// pedido y una respuesta (no hay ida y vuelta guardada en la base).
class ConversacionSolicitud extends StatefulWidget {
  final int solicitudId;
  const ConversacionSolicitud({super.key, required this.solicitudId});

  /// Se abre como pantalla propia (en el celular, a pantalla completa) con el
  /// mismo service de la lista, así al resolver se actualizan las dos.
  static Future<void> abrir(BuildContext context, SolicitudesService svc, Solicitud s) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: svc,
          child: ConversacionSolicitud(solicitudId: s.id),
        ),
      ));

  @override
  State<ConversacionSolicitud> createState() => _ConversacionSolicitudState();
}

class _ConversacionSolicitudState extends State<ConversacionSolicitud> {
  final _respuesta = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _respuesta.dispose();
    super.dispose();
  }

  Future<void> _resolver(SolicitudesService svc, Solicitud s, {required bool aprobar}) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = aprobar
        ? await svc.aprobar(s, respuesta: _respuesta.text)
        : await svc.rechazar(s, _respuesta.text);
    if (!mounted) return;
    setState(() {
      _guardando = false;
      _error = error;
    });
    if (error == null) {
      _respuesta.clear();
      mostrarExito(context, aprobar ? 'Solicitud aprobada.' : 'Solicitud rechazada.');
    }
  }

  Future<void> _imprimir(Solicitud s) async {
    try {
      final mensaje = await SolicitudPdfService.guardar(await SolicitudPdfService.pdf(s), s);
      if (mounted) mostrarExito(context, mensaje);
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo generar el PDF.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SolicitudesService>();
    final s = svc.porId(widget.solicitudId);
    if (s == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('La solicitud ya no está disponible.')));
    }
    final mia = svc.esMia(s);
    final pendiente = s.estado == EstadoSolicitud.pendiente;
    final responder = pendiente && svc.puedeAprobar;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F3),
      // Barra negra como la de la app.
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        surfaceTintColor: AppColors.negro,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(children: [
          _Avatar(nombre: s.solicitanteNombre),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.solicitanteNombre ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                [if (s.solicitanteRol != null) Rol.etiqueta(s.solicitanteRol!), TipoSolicitud.etiqueta(s.tipo)]
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ]),
          ),
        ]),
        actions: [
          if (svc.puedeImprimir(s))
            IconButton(
              tooltip: 'Constancia en PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFF87171)),
              onPressed: () => _imprimir(s),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            children: [
              Center(child: _EstadoChip(estado: s.estado)),
              const SizedBox(height: 14),
              // El pedido del área.
              _Burbuja(
                propia: mia,
                autor: mia ? 'Vos' : (s.solicitanteNombre ?? '—'),
                hora: s.fecha,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.asunto, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (s.itemDetalle != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.inventory_2_outlined, size: 15, color: Colors.black54),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${s.itemDetalle}'
                            '${s.cantidadSugerida == null ? '' : ' · ${fmtNum(s.cantidadSugerida)} ${s.itemUnidad ?? ''}'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  if (s.detalle != null) ...[
                    const SizedBox(height: 6),
                    Text(s.detalle!),
                  ],
                ]),
              ),
              // La respuesta de Gerencia (si ya resolvió).
              if (!pendiente)
                _Burbuja(
                  propia: !mia && svc.puedeAprobar,
                  autor: s.resueltaPorNombre ?? 'Gerencia',
                  hora: s.resueltaEn ?? s.fecha,
                  color: _EstadoChip.colorDe(s.estado).withValues(alpha: 0.10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          s.estado == EstadoSolicitud.aprobada
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 18,
                          color: _EstadoChip.colorDe(s.estado)),
                      const SizedBox(width: 6),
                      Text(s.estado.etiqueta,
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: _EstadoChip.colorDe(s.estado))),
                    ]),
                    if (s.respuesta != null) ...[
                      const SizedBox(height: 4),
                      Text(s.respuesta!),
                    ],
                  ]),
                )
              else if (!responder)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Center(
                    child: Text('Esperando respuesta de Gerencia…',
                        style: TextStyle(color: Colors.black45, fontStyle: FontStyle.italic)),
                  ),
                ),
            ],
          ),
        ),
        if (responder) _caja(svc, s),
      ]),
    );
  }

  /// Caja para responder, como la de un chat: el texto y dos botones.
  Widget _caja(SolicitudesService svc, Solicitud s) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
              ),
            TextField(
              controller: _respuesta,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              enabled: !_guardando,
              decoration: InputDecoration(
                hintText: 'Escribí una respuesta (obligatoria para rechazar)',
                counterText: '',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF4F6F8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                  ),
                  onPressed: _guardando ? null : () => _resolver(svc, s, aprobar: false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
                  onPressed: _guardando ? null : () => _resolver(svc, s, aprobar: true),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(_guardando ? 'Enviando…' : 'Aprobar'),
                ),
              ),
            ]),
          ]),
        ),
      );
}

class _Burbuja extends StatelessWidget {
  final bool propia;
  final String autor;
  final DateTime hora;
  final Color? color;
  final Widget child;
  const _Burbuja({
    required this.propia,
    required this.autor,
    required this.hora,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: propia ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho * 0.82 > 520 ? 520 : ancho * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: color ?? (propia ? const Color(0xFFDCF2E4) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(propia ? 14 : 3),
              bottomRight: Radius.circular(propia ? 3 : 14),
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(autor,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primario)),
            const SizedBox(height: 2),
            child,
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(fmtFechaHora(hora), style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Iniciales del nombre en un círculo, como la foto de un contacto.
class _Avatar extends StatelessWidget {
  final String? nombre;
  final double radio;
  const _Avatar({required this.nombre, this.radio = 18});

  @override
  Widget build(BuildContext context) {
    final partes = (nombre ?? '?').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final iniciales = partes.isEmpty
        ? '?'
        : (partes.first[0] + (partes.length > 1 ? partes[1][0] : '')).toUpperCase();
    return CircleAvatar(
      radius: radio,
      backgroundColor: AppColors.primario.withValues(alpha: 0.15),
      child: Text(iniciales,
          style: TextStyle(
              fontSize: radio * 0.75, fontWeight: FontWeight.w700, color: AppColors.primario)),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final EstadoSolicitud estado;
  const _EstadoChip({required this.estado});

  static Color colorDe(EstadoSolicitud e) => switch (e) {
        EstadoSolicitud.pendiente => const Color(0xFFD97706),
        EstadoSolicitud.aprobada => const Color(0xFF16A34A),
        EstadoSolicitud.rechazada => const Color(0xFFDC2626),
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: colorDe(estado).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(estado.etiqueta,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorDe(estado))),
      );
}

/// Una fila de la lista, como un chat de la bandeja de mensajes: quién, de
/// qué se trata, lo último que se dijo y cuándo.
class FilaConversacion extends StatelessWidget {
  final Solicitud s;
  final bool mia;
  final VoidCallback onTap;
  const FilaConversacion({super.key, required this.s, required this.mia, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pendiente = s.estado == EstadoSolicitud.pendiente;
    final ultimo = pendiente
        ? (s.detalle ?? s.itemDetalle ?? TipoSolicitud.etiqueta(s.tipo))
        : '${s.estado == EstadoSolicitud.aprobada ? '✓' : '✗'} '
            '${s.respuesta ?? s.estado.etiqueta}';
    final hora = s.resueltaEn ?? s.fecha;
    final hoy = DateTime.now();
    final esHoy = hora.year == hoy.year && hora.month == hoy.month && hora.day == hoy.day;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            _Avatar(nombre: mia ? 'Gerencia' : s.solicitanteNombre, radio: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(mia ? s.asunto : (s.solicitanteNombre ?? '—'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text(
                      esHoy
                          ? '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}'
                          : fmtFecha(hora),
                      style: TextStyle(
                          fontSize: 11.5,
                          color: pendiente ? _EstadoChip.colorDe(s.estado) : Colors.black45)),
                ]),
                if (!mia)
                  Text(s.asunto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
                Row(children: [
                  Expanded(
                    child: Text(ultimo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: _EstadoChip.colorDe(s.estado), shape: BoxShape.circle),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
