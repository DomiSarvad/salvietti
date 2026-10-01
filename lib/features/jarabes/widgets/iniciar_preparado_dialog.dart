import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../utils/notificaciones.dart';
import '../../../utils/texto.dart';
import '../../../widgets/formulario_widgets.dart';
import '../models/jarabes_modelos.dart';
import '../services/jarabes_service.dart';
import 'verificacion_insumos.dart';

/// Elegir sabor y cuántos preparados hacer hoy. Mientras se escribe, se ve
/// en vivo si el insumo alcanza; si no, se puede pedir a Almacén desde acá
/// mismo antes de iniciar.
class IniciarPreparadoDialog extends StatefulWidget {
  final JarabesService servicio;
  /// Sabores (normalizados con [sinTildes]) que Producción planificó para
  /// hoy: solo para resaltarlos primero en la lista, como referencia — no
  /// restringe elegir cualquier otro.
  final Set<String> saboresEnPlanHoy;
  /// Si viene de "Producción del día" con un sabor ya elegido: arranca con
  /// ese sabor seleccionado.
  final Sabor? saborInicial;
  const IniciarPreparadoDialog({
    super.key,
    required this.servicio,
    this.saboresEnPlanHoy = const {},
    this.saborInicial,
  });

  @override
  State<IniciarPreparadoDialog> createState() => _IniciarPreparadoDialogState();
}

class _IniciarPreparadoDialogState extends State<IniciarPreparadoDialog> {
  Sabor? _sabor;
  final _cantidad = TextEditingController();
  final _tanque = TextEditingController();
  List<VerificacionInsumo>? _verificacion;
  bool _verificando = false;
  bool _guardando = false;
  bool _pidiendo = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.saborInicial != null) {
      _sabor = widget.saborInicial;
      _programarVerificacion();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cantidad.dispose();
    _tanque.dispose();
    super.dispose();
  }

  double? get _cantidadValor {
    final t = _cantidad.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  void _programarVerificacion() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _verificar);
  }

  Future<void> _verificar() async {
    final sabor = _sabor;
    final cantidad = _cantidadValor;
    if (sabor == null || cantidad == null || cantidad <= 0) {
      setState(() => _verificacion = null);
      return;
    }
    setState(() => _verificando = true);
    try {
      final r = await widget.servicio.verificarInsumos(sabor.id, cantidad);
      if (!mounted || sabor.id != _sabor?.id || cantidad != _cantidadValor) return;
      setState(() {
        _verificacion = r;
        _verificando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verificacion = null;
        _verificando = false;
        _error = 'Ese sabor no tiene una receta activa, o no se pudo verificar el stock.';
      });
    }
  }

  Future<void> _pedirFaltantes() async {
    final v = _verificacion;
    if (v == null) return;
    setState(() => _pidiendo = true);
    final error = await widget.servicio.pedirFaltantes(v);
    if (!mounted) return;
    setState(() => _pidiendo = false);
    if (error == null) {
      mostrarExito(context, 'Se envió el pedido a Almacén.');
    } else {
      mostrarError(context, error);
    }
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final tanque = int.tryParse(_tanque.text.trim());
    final error = await widget.servicio.iniciarPreparado(
      saborId: _sabor?.id,
      cantidad: _cantidadValor,
      tanque: tanque,
    );
    if (!mounted) return;
    if (error == null) {
      mostrarExito(context, 'Preparado iniciado.');
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
      _verificar(); // por si el error fue justo por falta de stock
    }
  }

  InputDecoration _deco(String label, {String? ayuda}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  bool _enPlanHoy(Sabor s) => widget.saboresEnPlanHoy.contains(sinTildes(s.nombre));

  @override
  Widget build(BuildContext context) {
    final v = _verificacion;
    final hayFaltantes = v != null && v.any((i) => !i.alcanza);

    // Los del plan de hoy primero (solo para ubicarlos rápido); sigue
    // pudiéndose elegir cualquier otro sabor.
    final sabores = [...widget.servicio.sabores]..sort((a, b) {
        final pa = _enPlanHoy(a), pb = _enPlanHoy(b);
        if (pa != pb) return pa ? -1 : 1;
        return a.nombre.compareTo(b.nombre);
      });

    return ModalFormulario(
      titulo: 'Iniciar preparado',
      icono: Icons.play_circle_outline,
      textoBoton: 'Iniciar',
      guardando: _guardando,
      onGuardar: hayFaltantes ? null : _guardar,
      ancho: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Sabor>(
            initialValue: _sabor,
            decoration: _deco('Sabor'),
            items: [
              for (final s in sabores)
                DropdownMenuItem(
                  value: s,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.nombre),
                    if (_enPlanHoy(s)) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.today, size: 14, color: AppColors.primario),
                    ],
                  ]),
                ),
            ],
            onChanged: (s) {
              setState(() => _sabor = s);
              _programarVerificacion();
            },
          ),
          if (widget.saboresEnPlanHoy.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('📅 = está en el plan de hoy',
                  style: TextStyle(fontSize: 11, color: Colors.black45)),
            ),
          const SizedBox(height: 12),
          FilaCampos([
            TextField(
              controller: _cantidad,
              autofocus: widget.saborInicial != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _programarVerificacion(),
              decoration: _deco('Cantidad de preparados', ayuda: 'ej. 2, 1, 0.5'),
            ),
            TextField(
              controller: _tanque,
              keyboardType: TextInputType.number,
              decoration: _deco('Tanque (opcional)'),
            ),
          ]),
          const SizedBox(height: 12),
          if (_verificando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (v != null) ...[
            VerificacionInsumos(items: v),
            if (hayFaltantes) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pidiendo ? null : _pedirFaltantes,
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(_pidiendo ? 'Enviando…' : '¿Solicitar el faltante a Almacén?'),
              ),
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
