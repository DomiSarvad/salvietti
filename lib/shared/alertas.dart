import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Ventanas de aviso con ícono grande en un círculo, título grande y un
/// texto corto (pedido del usuario, tomado de otro sistema que le gustaba):
/// confirmar antes de algo que no se deshace, y "listo" después de guardar.
enum TipoAlerta { advertencia, pregunta, exito }

const _rojo = Color(0xFFDC2626);

({IconData icono, Color color}) _estilo(TipoAlerta t) => switch (t) {
      TipoAlerta.advertencia => (icono: Icons.priority_high_rounded, color: const Color(0xFFF0A65C)),
      TipoAlerta.pregunta => (icono: Icons.question_mark_rounded, color: const Color(0xFF87ADBD)),
      TipoAlerta.exito => (icono: Icons.check_rounded, color: const Color(0xFF8CCB74)),
    };

class _Alerta extends StatelessWidget {
  final TipoAlerta tipo;
  final String titulo;
  final String? texto;
  final Widget? extra;
  final List<Widget> botones;
  const _Alerta({required this.tipo, required this.titulo, this.texto, this.extra, this.botones = const []});

  @override
  Widget build(BuildContext context) {
    final e = _estilo(tipo);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Ícono en un círculo de borde claro, como el del ejemplo.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (_, escala, hijo) => Transform.scale(scale: escala, child: hijo),
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: e.color.withValues(alpha: 0.45), width: 3),
                ),
                child: Icon(e.icono, size: 42, color: e.color),
              ),
            ),
            const SizedBox(height: 16),
            Text(titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF545454))),
            if (texto != null) ...[
              const SizedBox(height: 8),
              Text(texto!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF545454))),
            ],
            if (extra != null) ...[const SizedBox(height: 14), extra!],
            if (botones.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(children: [
                for (var i = 0; i < botones.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: botones[i]),
                ],
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

ButtonStyle _boton(Color color) => FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );

/// Pregunta antes de hacer algo. [peligro]: el botón de "sí" va en rojo
/// (eliminar, anular); si no, en el verde de la app.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  String? texto,
  String textoSi = 'Sí',
  String textoNo = 'Cancelar',
  TipoAlerta tipo = TipoAlerta.advertencia,
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => _Alerta(
      tipo: tipo,
      titulo: titulo,
      texto: texto,
      botones: [
        FilledButton(
            style: _boton(const Color(0xFF6E7881)),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(textoNo)),
        FilledButton(
            style: _boton(peligro ? _rojo : AppColors.primario),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(textoSi)),
      ],
    ),
  );
  return r == true;
}

/// Como [confirmar], pero con un texto para escribir (el motivo de anular, o
/// observaciones). Devuelve lo escrito (vacío si es opcional y no se escribió
/// nada), o null si se canceló.
Future<String?> confirmarConMotivo(
  BuildContext context, {
  required String titulo,
  String? texto,
  String textoSi = 'Sí, anular',
  String etiqueta = 'Motivo',
  bool obligatorio = true,
  bool peligro = true,
  TipoAlerta tipo = TipoAlerta.advertencia,
}) {
  final ctrl = TextEditingController();
  String? error; // fuera del builder: si no, se borraba en cada redibujo
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      return _Alerta(
        tipo: tipo,
        titulo: titulo,
        texto: texto,
        extra: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 300,
          decoration: InputDecoration(labelText: etiqueta, errorText: error, border: const OutlineInputBorder()),
        ),
        botones: [
          FilledButton(
              style: _boton(const Color(0xFF6E7881)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              style: _boton(peligro ? _rojo : AppColors.primario),
              onPressed: () {
                if (obligatorio && ctrl.text.trim().isEmpty) {
                  setLocal(() => error = 'Escribí el motivo.');
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
              child: Text(textoSi)),
        ],
      );
    }),
  );
}

/// "Listo": se muestra después de guardar y se cierra solo (o tocando).
/// Se puede llamar justo antes de cerrar el formulario: aparece cuando el
/// formulario ya se cerró, sobre la pantalla de abajo.
void avisoExito(BuildContext context, String titulo, [String? texto]) {
  final nav = Navigator.of(context, rootNavigator: true);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!nav.mounted) return;
    Timer? cierre;
    showDialog<void>(
      context: nav.context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        cierre = Timer(const Duration(milliseconds: 1700), () {
          if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: _Alerta(tipo: TipoAlerta.exito, titulo: titulo, texto: texto),
        );
      },
    ).whenComplete(() => cierre?.cancel());
  });
}
