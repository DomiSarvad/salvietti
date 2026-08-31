import 'package:flutter/material.dart';

/// Campo con sugerencias tipo buscador: al escribir filtra entre las
/// opciones ya existentes en la base de datos (ej. proveedores usados
/// antes); si no coincide ninguna, se puede seguir escribiendo
/// libremente para registrar un valor nuevo (no exige elegir de la lista).
class AutocompletarTexto extends StatelessWidget {
  final String label;
  final String? valorInicial;
  final List<String> opciones;
  final ValueChanged<String> onChanged;

  const AutocompletarTexto({
    super.key,
    required this.label,
    required this.opciones,
    required this.onChanged,
    this.valorInicial,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: valorInicial ?? ''),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return opciones;
        return opciones.where((o) => o.toLowerCase().contains(query));
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: label),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 380),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options
                    .map((o) => ListTile(
                          dense: true,
                          title: Text(o),
                          onTap: () => onSelected(o),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
