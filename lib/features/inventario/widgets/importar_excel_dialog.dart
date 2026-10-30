import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../services/archivo_service.dart';
import '../../../shared/alertas.dart';
import '../../../utils/notificaciones.dart';
import '../../../widgets/formulario_widgets.dart';
import '../services/excel_inventario.dart';
import '../services/inventario_service.dart';

const _mimeXlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Importar ítems de Excel al almacén elegido: descargar la plantilla, elegir
/// el archivo, ver qué se va a crear (y qué filas tienen error) e importar.
class ImportarExcelInventarioDialog extends StatefulWidget {
  final InventarioService servicio;
  const ImportarExcelInventarioDialog({super.key, required this.servicio});

  @override
  State<ImportarExcelInventarioDialog> createState() => _ImportarExcelInventarioDialogState();
}

class _ImportarExcelInventarioDialogState extends State<ImportarExcelInventarioDialog> {
  LecturaExcel? _lectura;
  String? _archivo;
  bool _cargarStock = true;
  bool _importando = false;
  int _hechos = 0;
  int _total = 0;

  InventarioService get _svc => widget.servicio;

  Future<void> _plantilla() async {
    try {
      final msg = await ArchivoService.guardar(await _svc.plantillaExcel(),
          nombre: _svc.nombrePlantilla, ext: 'xlsx', mimeType: _mimeXlsx);
      if (mounted) mostrarInfo(context, msg);
    } catch (_) {
      if (mounted) mostrarError(context, 'No se pudo descargar la plantilla.');
    }
  }

  Future<void> _elegir() async {
    final r = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    final a = r?.files.firstOrNull;
    if (a?.bytes == null) return;
    setState(() {
      _archivo = a!.name;
      _lectura = _svc.leerExcel(a.bytes!);
    });
  }

  Future<void> _importar() async {
    final l = _lectura;
    if (l == null) return;
    setState(() {
      _importando = true;
      _hechos = 0;
      _total = l.nuevos.length;
    });
    final r = await _svc.importarExcel(l, cargarStock: _cargarStock, progreso: (h, t) {
      if (mounted) {
        setState(() {
          _hechos = h;
          _total = t;
        });
      }
    });
    if (!mounted) return;
    if (r.errores.isEmpty) {
      avisoExito(context, 'Importado',
          '${r.creados} ítem${r.creados == 1 ? '' : 's'} nuevo${r.creados == 1 ? '' : 's'}'
              '${r.contados > 0 ? ' · stock cargado en ${r.contados}' : ''}.');
      Navigator.pop(context, true);
      return;
    }
    setState(() => _importando = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Se importó con avisos (${r.creados} creados)'),
        content: SingleChildScrollView(child: Text(r.errores.join('\n'))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = _lectura;
    final puedeImportar = !_importando &&
        l != null &&
        l.errorGeneral == null &&
        (l.nuevos.isNotEmpty || (_cargarStock && l.conStock > 0));
    return ModalFormulario(
      titulo: 'Importar Excel',
      icono: Icons.upload_file_outlined,
      textoBoton: l == null ? 'Importar' : 'Importar ${l.nuevos.length} ítem${l.nuevos.length == 1 ? '' : 's'}',
      guardando: _importando,
      onGuardar: puedeImportar ? _importar : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Paso 1 y 2: plantilla y archivo.
        OutlinedButton.icon(
          onPressed: _plantilla,
          icon: const Icon(Icons.download_outlined),
          label: const Text('1. Descargar la plantilla'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primario),
          onPressed: _importando ? null : _elegir,
          icon: const Icon(Icons.table_view_outlined),
          label: Text(_archivo == null ? '2. Elegir el Excel' : 'Cambiar archivo ($_archivo)'),
        ),
        if (l?.errorGeneral != null) ...[
          const SizedBox(height: 12),
          Text(l!.errorGeneral!, style: const TextStyle(color: Color(0xFFDC2626))),
        ],
        if (l != null && l.errorGeneral == null) ...[
          const SizedBox(height: 16),
          // Resumen de lo que se va a hacer.
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pastilla('${l.nuevos.length} nuevos', AppColors.primario),
            _Pastilla('${l.existentes.length} ya existen', Colors.black54),
            if (l.conError.isNotEmpty) _Pastilla('${l.conError.length} con error', const Color(0xFFDC2626)),
          ]),
          if (l.columnasExtra.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF5C26B)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: Color(0xFFB7791F), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Columnas nuevas: ${l.columnasExtra.join(', ')}. Se guardan en la ficha de '
                    'cada ítem nuevo como "Otros datos"'
                    '${l.existentes.isEmpty ? '' : ' (en los que ya existen no se cambian)'}.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ]),
            ),
          if (l.conStock > 0)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _cargarStock,
              onChanged: _importando ? null : (v) => setState(() => _cargarStock = v ?? false),
              title: Text('Cargar el stock (${l.conStock}) como conteo físico'),
            ),
          if (_importando && _total > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _hechos / _total),
            Text('Creando $_hechos de $_total…', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          for (final f in [...l.conError, ...l.nuevos.take(30)])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                f.error != null ? Icons.error_outline : Icons.add_circle_outline,
                color: f.error != null ? const Color(0xFFDC2626) : AppColors.primario,
                size: 20,
              ),
              title: Text('Fila ${f.fila} · ${f.detalle}'),
              subtitle: f.error != null
                  ? Text(f.error!, style: const TextStyle(color: Color(0xFFDC2626)))
                  : Text(_svc.textoRuta(f.nuevo!.categoriaId)),
            ),
          if (l.nuevos.length > 30)
            Text('…y ${l.nuevos.length - 30} más.', style: const TextStyle(color: Colors.black54)),
        ],
      ]),
    );
  }
}

class _Pastilla extends StatelessWidget {
  final String texto;
  final Color color;
  const _Pastilla(this.texto, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      );
}
