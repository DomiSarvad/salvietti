import 'package:flutter/material.dart';

/// Pide un texto obligatorio corto (motivo de anulación, resolución de una
/// observación). Devuelve el texto guardado, o null si se cancela.
Future<String?> pedirMotivo(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required Future<String?> Function(String texto) onConfirmar,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _MotivoDialog(titulo: titulo, etiqueta: etiqueta, onConfirmar: onConfirmar),
  );
}

class _MotivoDialog extends StatefulWidget {
  final String titulo;
  final String etiqueta;
  final Future<String?> Function(String texto) onConfirmar;
  const _MotivoDialog({required this.titulo, required this.etiqueta, required this.onConfirmar});

  @override
  State<_MotivoDialog> createState() => _MotivoDialogState();
}

class _MotivoDialogState extends State<_MotivoDialog> {
  final _ctrl = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.onConfirmar(_ctrl.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, _ctrl.text);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            decoration: InputDecoration(labelText: widget.etiqueta, counterText: ''),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFDC2626))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _confirmar,
          child: Text(_guardando ? 'Guardando…' : 'Confirmar'),
        ),
      ],
    );
  }
}
