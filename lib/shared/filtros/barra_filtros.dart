import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/formatters.dart';
import '../../utils/notificaciones.dart';
import '../reportes/reporte_tabla.dart';
import 'filtro_lista.dart';

/// Buscador común de todas las listas: texto + fechas Desde/Hasta, y botones
/// PDF/Excel que exportan EXACTAMENTE lo filtrado (el filtro es el filtro del
/// reporte, no hace falta armar uno aparte).
///
/// La pantalla le pasa el filtro actual y a quién avisarle los cambios (su
/// service), y cómo armar el reporte ([reporte], del service). Sin [reporte]
/// no muestra los botones; con [conFechas] en false, solo el buscador.
class BarraFiltros extends StatefulWidget {
  final FiltroLista filtro;
  final ValueChanged<FiltroLista> onCambio;
  final ReporteTabla Function()? reporte;
  final bool conFechas;
  final String hint;

  const BarraFiltros({
    super.key,
    required this.filtro,
    required this.onCambio,
    this.reporte,
    this.conFechas = true,
    this.hint = 'Buscar…',
  });

  @override
  State<BarraFiltros> createState() => _BarraFiltrosState();
}

class _BarraFiltrosState extends State<BarraFiltros> {
  late final _texto = TextEditingController(text: widget.filtro.texto);
  Timer? _espera;
  bool _exportando = false;

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  /// Se aplica cuando se deja de escribir (no a cada letra).
  void _alEscribir(String t) {
    setState(() {}); // muestra/oculta la "x"
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), () => widget.onCambio(widget.filtro.conTexto(t)));
  }

  void _limpiarTexto() {
    _texto.clear();
    _espera?.cancel();
    setState(() {});
    widget.onCambio(widget.filtro.conTexto(''));
  }

  Future<void> _elegirFecha({required bool desde}) async {
    final actual = desde ? widget.filtro.desde : widget.filtro.hasta;
    final otra = desde ? widget.filtro.hasta : widget.filtro.desde;
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual ?? otra ?? hoy,
      firstDate: DateTime(2020),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      helpText: desde ? 'Desde' : 'Hasta',
    );
    if (elegida == null) return;
    var f = desde ? widget.filtro.conDesde(elegida) : widget.filtro.conHasta(elegida);
    // Si quedaron al revés, se acomodan solas (no se muestra un error por eso).
    if (f.desde != null && f.hasta != null && f.desde!.isAfter(f.hasta!)) {
      f = FiltroLista(texto: f.texto, desde: f.hasta, hasta: f.desde);
    }
    widget.onCambio(f);
  }

  Future<void> _exportar({required bool pdf}) async {
    final armar = widget.reporte;
    if (armar == null) return;
    final responsable = context.read<AuthService>().usuarioActual?.nombreCompleto ?? '—';
    setState(() => _exportando = true);
    try {
      final r = armar();
      if (pdf) {
        await ReporteTablaExport.guardarPdf(
            await ReporteTablaExport.pdf(r, responsable: responsable), r);
      } else {
        await ReporteTablaExport.guardarExcel(ReporteTablaExport.excel(r, responsable: responsable), r);
      }
      if (mounted) {
        mostrarExito(context, '${pdf ? 'PDF' : 'Excel'} generado con ${r.filas.length} registro'
            '${r.filas.length == 1 ? '' : 's'}.');
      }
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo generar el archivo.');
    }
    if (mounted) setState(() => _exportando = false);
  }

  Widget _campoFecha({required bool desde}) {
    final valor = desde ? widget.filtro.desde : widget.filtro.hasta;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _elegirFecha(desde: desde),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: desde ? 'Desde' : 'Hasta',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.event_outlined, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: valor == null
              ? null
              : IconButton(
                  tooltip: 'Quitar fecha',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => widget.onCambio(
                      desde ? widget.filtro.conDesde(null) : widget.filtro.conHasta(null)),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(valor == null ? 'dd/mm/aaaa' : fmtFecha(valor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: valor == null ? Colors.black38 : Colors.black87)),
      ),
    );
  }

  Widget _botonExportar({required bool pdf}) {
    final color = pdf ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: pdf ? 'Descargar en PDF lo que se ve' : 'Descargar en Excel lo que se ve',
        child: IconButton(
          onPressed: _exportando ? null : () => _exportar(pdf: pdf),
          // Blanco con un tinte de su color y relieve, como los demás botones.
          style: IconButton.styleFrom(
            backgroundColor: Color.alphaBlend(color.withValues(alpha: 0.07), Colors.white),
            side: BorderSide(color: color.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1.5,
            shadowColor: color.withValues(alpha: 0.4),
          ),
          icon: Icon(pdf ? Icons.picture_as_pdf_outlined : Icons.table_view_outlined, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _texto,
              onChanged: _alEscribir,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _texto.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close), onPressed: _limpiarTexto),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (widget.reporte != null) ...[
            _botonExportar(pdf: true),
            _botonExportar(pdf: false),
          ],
        ]),
        if (widget.conFechas) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _campoFecha(desde: true)),
            const SizedBox(width: 8),
            Expanded(child: _campoFecha(desde: false)),
          ]),
        ],
      ],
    );
  }
}

/// Lo que se muestra en vez de la lista cuando hay filtros y nada coincide
/// (distinto de "todavía no hay registros": acá sí hay, pero no con esto).
class SinResultados extends StatelessWidget {
  const SinResultados({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No hay resultados con estos filtros.\nProbá con otra búsqueda u otras fechas.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ),
      );
}
