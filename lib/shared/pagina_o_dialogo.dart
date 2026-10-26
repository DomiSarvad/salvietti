import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Abre un formulario como PÁGINA en el celular (pantalla completa, barra
/// negra con flecha de volver, como el detalle del Informe de Producción) y
/// como VENTANA en la compu. [builder] recibe si es página, para que el
/// formulario se arme sin el marco de diálogo. En los dos casos se cierra
/// con `Navigator.pop(context, resultado)`.
Future<T?> abrirPaginaODialogo<T>(
  BuildContext context, {
  required String titulo,
  required Widget Function(bool comoPagina) builder,
}) {
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(context: context, builder: (_) => builder(false));
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        surfaceTintColor: AppColors.negro,
        foregroundColor: Colors.white,
        title: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(top: false, child: builder(true)),
    ),
  ));
}
