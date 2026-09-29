import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Selector de rol tipo desplegable con buscador: un cuadro de búsqueda arriba
/// y la lista de roles debajo. Devuelve el id del rol elegido (ej.
/// 'almacen') o null si se cancela.
Future<String?> elegirRol(BuildContext context, {String? actual}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SelectorRolDialog(actual: actual),
  );
}

String _sinTildes(String t) => t
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

class _SelectorRolDialog extends StatefulWidget {
  final String? actual;
  const _SelectorRolDialog({this.actual});

  @override
  State<_SelectorRolDialog> createState() => _SelectorRolDialogState();
}

class _SelectorRolDialogState extends State<_SelectorRolDialog> {
  String _consulta = '';

  @override
  Widget build(BuildContext context) {
    final q = _sinTildes(_consulta.trim());
    final roles =
        Rol.todos.where((r) => q.isEmpty || _sinTildes(Rol.etiqueta(r)).contains(q)).toList();
    final ancho = (MediaQuery.of(context).size.width - 32).clamp(280.0, 380.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: ancho,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _consulta = v),
                  onSubmitted: (_) {
                    if (roles.length == 1) Navigator.pop(context, roles.first);
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar rol...',
                    suffixIcon: const Icon(Icons.search, color: Colors.black45),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade400)),
                    focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        borderSide: BorderSide(color: AppColors.primario, width: 1.6)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                if (roles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Sin resultados.', style: TextStyle(color: Colors.black54)),
                  ),
                for (int i = 0; i < roles.length; i++) ...[
                  if (i == 0 || Rol.area(roles[i]) != Rol.area(roles[i - 1]))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                      child: Text(Rol.area(roles[i]).toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                              color: Colors.black45)),
                    ),
                  ListTile(
                    dense: true,
                    selected: roles[i] == widget.actual,
                    selectedTileColor: AppColors.primario,
                    selectedColor: Colors.white,
                    title: Text(Rol.etiqueta(roles[i])),
                    onTap: () => Navigator.pop(context, roles[i]),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
