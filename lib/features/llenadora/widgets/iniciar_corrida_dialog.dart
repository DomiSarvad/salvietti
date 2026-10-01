import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/llenadora_modelos.dart';
import '../services/llenadora_service.dart';

/// Inicia una corrida de Llenadora: turno, sabor, formato, y opcional el
/// preparado de Jarabes que se va a envasar (si no está en el sistema, se
/// puede escribir el lote y el tanque a mano) y la tapa a usar. La hora de
/// inicio la pone el servidor.
class IniciarCorridaDialog extends StatefulWidget {
  final LlenadoraService servicio;
  const IniciarCorridaDialog({super.key, required this.servicio});

  @override
  State<IniciarCorridaDialog> createState() => _IniciarCorridaDialogState();
}

class _IniciarCorridaDialogState extends State<IniciarCorridaDialog> {
  Turno? _turno;
  Sabor? _sabor;
  Presentacion? _presentacion;
  PreparadoJarabes? _preparado;
  List<PreparadoJarabes> _preparados = [];
  final _lote = TextEditingController();
  final _tanque = TextEditingController();
  ItemInventario? _tapa;
  Set<int>? _presentacionesValidas;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _lote.dispose();
    _tanque.dispose();
    super.dispose();
  }

  Future<void> _elegirSabor(Sabor? s) async {
    setState(() {
      _sabor = s;
      _presentacion = null;
      _presentacionesValidas = null;
      _preparado = null;
      _preparados = [];
    });
    if (s == null) return;
    final r = await Future.wait([
      widget.servicio.presentacionesDe(s.id),
      widget.servicio.preparadosDe(s.id),
    ]);
    if (!mounted || _sabor?.id != s.id) return;
    setState(() {
      _presentacionesValidas = r[0] as Set<int>;
      _preparados = r[1] as List<PreparadoJarabes>;
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
      preparadoId: _preparado?.id,
      nLotePreparado: _preparado == null ? _lote.text : null,
      tanque: _preparado == null ? _tanque.text : null,
      itemTapaId: _tapa?.id,
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
      titulo: 'Iniciar corrida de Llenadora',
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
                DropdownMenuItem(value: p, child: Text('${p.nombre} (${p.material == 'pet' ? 'PET' : 'Vidrio'})')),
            ],
            onChanged: _sabor == null ? null : (v) => setState(() => _presentacion = v),
          ),
          const SizedBox(height: 12),
          if (_preparados.isNotEmpty) ...[
            DropdownButtonFormField<PreparadoJarabes>(
              initialValue: _preparado,
              decoration: _deco('Preparado de Jarabes (opcional)',
                  ayuda: 'Si no está el que buscás, dejalo vacío y escribí el lote a mano'),
              items: [
                const DropdownMenuItem(value: null, child: Text('— Sin vincular —')),
                for (final p in _preparados)
                  DropdownMenuItem(
                      value: p,
                      child: Text('Lote ${p.nLote}${p.tanque == null ? '' : ' · Tanque ${p.tanque}'}')),
              ],
              onChanged: (v) => setState(() => _preparado = v),
            ),
            const SizedBox(height: 12),
          ],
          if (_preparado == null)
            FilaCampos([
              TextField(controller: _lote, decoration: _deco('N° de lote (opcional)')),
              TextField(controller: _tanque, decoration: _deco('Tanque (opcional)')),
            ]),
          const SizedBox(height: 12),
          Autocomplete<ItemInventario>(
            displayStringForOption: (i) => '${i.codigo} · ${i.detalle}',
            optionsBuilder: (t) => svc.buscarTapas(t.text),
            onSelected: (i) => setState(() => _tapa = i),
            fieldViewBuilder: (context, c, foco, _) => TextField(
              controller: c,
              focusNode: foco,
              onChanged: (t) {
                if (_tapa != null && t != '${_tapa!.codigo} · ${_tapa!.detalle}') _tapa = null;
              },
              decoration: _deco('Tapa a usar (opcional)',
                  ayuda: 'Solo para identificarla en el reporte de mermas'),
            ),
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
