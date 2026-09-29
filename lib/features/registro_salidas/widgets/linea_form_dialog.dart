import 'package:flutter/material.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/salidas_modelos.dart';
import '../services/salidas_service.dart';

/// Alta o edición de una línea del reporte: sabor, formato y, según el
/// material, los campos de PET (palets, paquetes libres, botellas libres)
/// o de Vidrio (filas, cajas libres, botellas libres).
class LineaFormDialog extends StatefulWidget {
  final SalidasService servicio;
  final ReporteSalidas reporte;
  final LineaSalidas? linea;
  const LineaFormDialog({super.key, required this.servicio, required this.reporte, this.linea});

  @override
  State<LineaFormDialog> createState() => _LineaFormDialogState();
}

class _LineaFormDialogState extends State<LineaFormDialog> {
  Sabor? _sabor;
  Presentacion? _presentacion;
  Set<int>? _presentacionesValidas;
  final _petPalets = TextEditingController();
  final _petPaquetesLibres = TextEditingController();
  final _petBotellasLibres = TextEditingController();
  final _vidFilas = TextEditingController();
  final _vidCajasLibres = TextEditingController();
  final _vidBotellasLibres = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final l = widget.linea;
    if (l != null) {
      _sabor = widget.servicio.sabores.where((s) => s.id == l.saborId).firstOrNull;
      _presentacion =
          widget.servicio.presentaciones.where((p) => p.id == l.presentacionId).firstOrNull;
      _petPalets.text = l.petPalets?.toString() ?? '';
      _petPaquetesLibres.text = l.petPaquetesLibres?.toString() ?? '';
      _petBotellasLibres.text = l.petBotellasLibres?.toString() ?? '';
      _vidFilas.text = l.vidFilas?.toString() ?? '';
      _vidCajasLibres.text = l.vidCajasLibres?.toString() ?? '';
      _vidBotellasLibres.text = l.vidBotellasLibres?.toString() ?? '';
      if (_sabor != null) _cargarPresentaciones(_sabor!.id, silencioso: true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _petPalets, _petPaquetesLibres, _petBotellasLibres,
      _vidFilas, _vidCajasLibres, _vidBotellasLibres,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarPresentaciones(int saborId, {bool silencioso = false}) async {
    final validas = await widget.servicio.presentacionesDe(saborId);
    if (mounted && _sabor?.id == saborId) setState(() => _presentacionesValidas = validas);
  }

  Future<void> _elegirSabor(Sabor? s) async {
    setState(() {
      _sabor = s;
      _presentacion = null;
      _presentacionesValidas = null;
    });
    if (s != null) await _cargarPresentaciones(s.id);
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _guardar() async {
    if (_sabor == null || _presentacion == null) {
      setState(() => _error = 'Elegí el sabor y el formato.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.servicio.guardarLinea(
      widget.reporte,
      DatosLinea(
        id: widget.linea?.id,
        saborId: _sabor!.id,
        presentacionId: _presentacion!.id,
        petPalets: _num(_petPalets),
        petPaquetesLibres: _num(_petPaquetesLibres),
        petBotellasLibres: _num(_petBotellasLibres),
        vidFilas: _num(_vidFilas),
        vidCajasLibres: _num(_vidCajasLibres),
        vidBotellasLibres: _num(_vidBotellasLibres),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, widget.linea == null ? 'Sabor agregado.' : 'Línea actualizada.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _campoNum(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _deco(label),
      );

  @override
  Widget build(BuildContext context) {
    final svc = widget.servicio;
    final presentacionesDisponibles = _presentacionesValidas == null
        ? const <Presentacion>[]
        : svc.presentaciones.where((p) => _presentacionesValidas!.contains(p.id)).toList();

    return ModalFormulario(
      titulo: widget.linea == null ? 'Agregar sabor al reporte' : 'Editar línea',
      icono: Icons.playlist_add,
      textoBoton: 'Guardar',
      guardando: _guardando,
      onGuardar: _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [for (final s in svc.sabores) DropdownMenuItem(value: s, child: Text(s.nombre))],
            onChanged: _elegirSabor,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Presentacion>(
            initialValue: _presentacion,
            decoration: _deco('Formato'),
            items: [
              for (final p in presentacionesDisponibles)
                DropdownMenuItem(
                    value: p, child: Text('${p.nombre} (${p.esPet ? 'PET' : 'Vidrio'})')),
            ],
            onChanged: _sabor == null ? null : (v) => setState(() => _presentacion = v),
          ),
          if (_presentacion != null) ...[
            const SizedBox(height: 16),
            if (_presentacion!.esPet) ...[
              const Text('PET', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _campoNum(_petPalets, 'Palets')),
                const SizedBox(width: 10),
                Expanded(child: _campoNum(_petPaquetesLibres, 'Paquetes libres')),
                const SizedBox(width: 10),
                Expanded(child: _campoNum(_petBotellasLibres, 'Botellas libres')),
              ]),
            ] else ...[
              const Text('Vidrio', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                  'El total en botellas todavía no cuenta las "filas" (falta definir cuántas '
                  'cajas arma un palet); cajas y botellas libres sí se suman.',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _campoNum(_vidFilas, 'Filas')),
                const SizedBox(width: 10),
                Expanded(child: _campoNum(_vidCajasLibres, 'Cajas libres')),
                const SizedBox(width: 10),
                Expanded(child: _campoNum(_vidBotellasLibres, 'Botellas libres')),
              ]),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
        ],
      ),
    );
  }
}
