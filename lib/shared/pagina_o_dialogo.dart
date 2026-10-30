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

/// Para los formularios armados como [DialogoAdaptable]: ventana en la
/// compu, página aparte en el celular. Se cierra igual en los dos casos
/// (`Navigator.pop(context, resultado)`).
Future<T?> abrirAdaptable<T>(BuildContext context, WidgetBuilder builder) {
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<T>(context: context, builder: builder);
  }
  return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
}

/// Un `AlertDialog` que, abierto como página ([abrirAdaptable] en el
/// celular), se dibuja a pantalla completa con la barra negra y los botones
/// abajo. Lo decide la ruta donde está, así el formulario no cambia.
class DialogoAdaptable extends StatelessWidget {
  final String titulo;
  final Widget contenido;
  final List<Widget> acciones;

  /// Tamaño del contenido como ventana (como página ocupa todo).
  final double? ancho;
  final double? alto;

  /// Falso si [contenido] ya se desplaza solo o usa `Expanded` (una lista).
  final bool desplazar;

  const DialogoAdaptable({
    super.key,
    required this.titulo,
    required this.contenido,
    this.acciones = const [],
    this.ancho,
    this.alto,
    this.desplazar = true,
  });

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context) is! PageRoute) {
      return AlertDialog(
        title: Text(titulo),
        scrollable: desplazar,
        content: ancho == null && alto == null
            ? contenido
            : SizedBox(width: ancho, height: alto, child: contenido),
        actions: acciones,
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        surfaceTintColor: AppColors.negro,
        foregroundColor: Colors.white,
        title: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: desplazar
                ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: contenido)
                : Padding(padding: const EdgeInsets.all(16), child: contenido),
          ),
          if (acciones.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
              ),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: acciones,
              ),
            ),
        ]),
      ),
    );
  }
}

/// Igual que `AlertDialog` (mismos parámetros), pero en el celular (< 600 px)
/// ocupa toda la pantalla: barra negra con flecha de volver, el contenido y
/// los botones abajo. Para pasar un formulario hecho con AlertDialog basta con
/// cambiarle el nombre.
class AlertDialogAdaptable extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  const AlertDialogAdaptable({super.key, this.title, this.content, this.actions, this.scrollable = false});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 600) {
      return AlertDialog(title: title, content: content, actions: actions, scrollable: scrollable);
    }
    return Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.negro,
          surfaceTintColor: AppColors.negro,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
          titleSpacing: 0,
          title: title == null
              ? null
              : DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title!,
                ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: content),
        ),
        bottomNavigationBar: actions == null || actions!.isEmpty
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE3E7EB))),
                  ),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: actions!,
                  ),
                ),
              ),
      ),
    );
  }
}
