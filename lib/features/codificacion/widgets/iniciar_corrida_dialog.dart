import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/codificacion_modelos.dart';
import '../services/codificacion_service.dart';

/// Inicia una corrida de Codificación: turno, sabor, formato, y opcional la
/// corrida de Llenadora de la que viene (para trazabilidad), el N° de lote,
/// y el solvente/tinta que se van a usar.
class IniciarCorridaDialog extends StatefulWidget {
  final CodificacionService servicio;
  const IniciarCorridaDialog({super.key, required this.servicio});

  @override
  State<IniciarCorridaDialog> createState() => _IniciarCorridaDialogState();
}

class _IniciarCorridaDialogState extends State<IniciarCorridaDialog> {
  Turno? _turno;
  Sabor? _sabor;
  Presentacion? _presentacion;
  CorridaLlenadoraRef? _corridaLlenadora;
  List<CorridaLlenadoraRef> _corridasLlenadora = [];
  final _lote = TextEditingController();
  ItemInventario? _solvente;
  ItemInventario? _tinta;
  Set<int>? _presentacionesValidas;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _lote.dispose();
    super.dispose();
  }

  Future<void> _elegirSabor(Sabor? s) async {
    setState(() {
      _sabor = s;
      _presentacion = null;
      _presentacionesValidas = null;
      _corridaLlenadora = null;
      _corridasLlenadora = [];
    });
    if (s == null) return;
    final r = await Future.wait([
      widget.servicio.presentacionesDe(s.id),
      widget.servicio.corridasLlenadoraDe(s.id),
    ]);
    if (!mounted || _sabor?.id != s.id) return;
    setState(() {
      _presentacionesValidas = r[0] as Set<int>;
      _corridasLlenadora = r[1] as List<CorridaLlenadoraRef>;
    });
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.iniciarCorrida(
      turno: _turno?.id,
      saborId: _sabor?.id,
      presentacionId: _presentacion?.id,
      corridaLlenadoraId: _corridaLlenadora?.id,
      nLote: _lote.text,
      itemSolventeId: _solvente?.id,
      itemTintaId: _tinta?.id,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Corrida iniciada.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label, {String? ayuda}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final svc = widget.servicio;
    final presentacionesDisponibles = _presentacionesValidas == null
        ? const <Presentacion>[]
        : svc.presentaciones.where((p) => _presentacionesValidas!.contains(p.id)).toList();

    return ModalFormulario(
      titulo: 'Iniciar corrida de Codificación',
      icono: Icons.play_circle_outline,
      textoBoton: 'Iniciar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Turno>(
            initialValue: _turno,
            decoration: _deco('Turno'),
            items: [
              for (final t in Turno.values) DropdownMenuItem(value: t, child: Text(t.etiqueta)),
            ],
            onChanged: (v) => setState(() => _turno = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [
              for (final s in svc.sabores) DropdownMenuItem(value: s, child: Text(s.nombre)),
            ],
            onChanged: _elegirSabor,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Presentacion>(
            initialValue: _presentacion,
            decoration: _deco('Formato',
                ayuda: _sabor == null
                    ? 'Elegí primero el sabor'
                    : (presentacionesDisponibles.isEmpty ? 'Ese sabor no tiene formatos cargados' : null)),
            items: [
              for (final p in presentacionesDisponibles)
                DropdownMenuItem(value: p, child: Text(p.nombre)),
            ],
            onChanged: _sabor == null ? null : (v) => setState(() => _presentacion = v),
          ),
          const SizedBox(height: 12),
          if (_corridasLlenadora.isNotEmpty) ...[
            DropdownButtonFormField<CorridaLlenadoraRef>(
              initialValue: _corridaLlenadora,
              decoration: _deco('Corrida de Llenadora (opcional)',
                  ayuda: 'Para saber de qué corrida vienen estas botellas'),
              items: [
                const DropdownMenuItem(value: null, child: Text('— Sin vincular —')),
                for (final c in _corridasLlenadora)
                  DropdownMenuItem(value: c, child: Text('Corrida #${c.id} (${c.turno})')),
              ],
              onChanged: (v) => setState(() => _corridaLlenadora = v),
            ),
            const SizedBox(height: 12),
          ],
          TextField(controller: _lote, decoration: _deco('N° de lote (opcional)')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Autocomplete<ItemInventario>(
                  displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
                  optionsBuilder: (t) => svc.buscarItems(t.text),
                  onSelected: (i) => setState(() => _solvente = i),
                  fieldViewBuilder: (context, c, foco, _) => TextField(
                    controller: c,
                    focusNode: foco,
                    onChanged: (t) {
                      if (_solvente != null && t != '${_solvente!.codigo} · ${_solvente!.detalle}') {
                        _solvente = null;
                      }
                    },
                    decoration: _deco('Solvente (opcional)'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Autocomplete<ItemInventario>(
                  displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
                  optionsBuilder: (t) => svc.buscarItems(t.text),
                  onSelected: (i) => setState(() => _tinta = i),
                  fieldViewBuilder: (context, c, foco, _) => TextField(
                    controller: c,
                    focusNode: foco,
                    onChanged: (t) {
                      if (_tinta != null && t != '${_tinta!.codigo} · ${_tinta!.detalle}') {
                        _tinta = null;
                      }
                    },
                    decoration: _deco('Tinta (opcional)'),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }
}
