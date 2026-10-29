import 'package:flutter/material.dart';
import '../../../shared/alertas.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/notificaciones.dart';
import '../repositories/inventario_repository.dart';
import '../services/balance_service.dart';

/// Balance de insumos: se escribe la cantidad real de cada ítem del almacén y
/// se guarda todo junto. Las filas que quedan vacías no se tocan.
/// Devuelve `true` al volver si se guardó algo.
class BalanceScreen extends StatelessWidget {
  final String almacenId;
  final String almacenNombre;
  const BalanceScreen({super.key, required this.almacenId, required this.almacenNombre});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) =>
          BalanceService(SupabaseInventarioRepository(), usuario, almacenId)..cargar(),
      child: _Vista(almacenNombre: almacenNombre),
    );
  }
}

class _Vista extends StatelessWidget {
  final String almacenNombre;
  const _Vista({required this.almacenNombre});

  Future<void> _guardar(BuildContext context, BalanceService svc) async {
    final nota = await showDialog<String>(
      context: context,
      builder: (_) => _ConfirmarDialog(contados: svc.contados, diferencias: svc.conDiferencia),
    );
    if (nota == null || !context.mounted) return;
    final error = await svc.guardar(nota: nota);
    if (!context.mounted) return;
    if (error == null) {
      avisoExito(context, 'Balance registrado');
      Navigator.pop(context, true);
    } else {
      mostrarError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BalanceService>();

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: AppColors.negro,
        foregroundColor: Colors.white,
        title: Text('Balance de insumos · $almacenNombre'),
      ),
      body: _cuerpo(context, svc),
      bottomNavigationBar: svc.cargando || svc.error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primario,
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: svc.guardando || !svc.puedeEditar
                      ? null
                      : () => _guardar(context, svc),
                  icon: svc.guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: Text('Guardar balance (${svc.contados})'),
                ),
              ),
            ),
    );
  }

  Widget _cuerpo(BuildContext context, BalanceService svc) {
    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.cargar, child: const Text('Reintentar')),
        ]),
      );
    }
    if (!svc.puedeEditar) {
      return const Center(child: Text('No tenés permiso para hacer el balance de este almacén.'));
    }

    final filas = svc.visibles;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escribí lo que contaste de cada ítem. Los que dejes vacíos no se modifican. '
                'Fecha: ${fmtFecha(DateTime.now())}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: svc.buscar,
                decoration: InputDecoration(
                  hintText: 'Buscar…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                _Dato('Contados', '${svc.contados} / ${svc.filas.length}', AppColors.primario),
                _Dato('Con diferencia', '${svc.conDiferencia}', const Color(0xFFD97706)),
                if (svc.invalidos > 0)
                  _Dato('Inválidos', '${svc.invalidos}', const Color(0xFFDC2626)),
              ]),
            ],
          ),
        ),
        Expanded(
          child: filas.isEmpty
              ? const Center(child: Text('No hay ítems para mostrar.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filas.length,
                  itemBuilder: (_, i) {
                    final f = filas[i];
                    final nuevaCategoria =
                        i == 0 || filas[i - 1].categoriaRaiz != f.categoriaRaiz;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nuevaCategoria)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
                            child: Text(f.categoriaRaiz.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black45)),
                          ),
                        _FilaWidget(key: ValueKey(f.item.itemId), fila: f, svc: svc),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color color;
  const _Dato(this.etiqueta, this.valor, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('$etiqueta: $valor',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}

class _FilaWidget extends StatelessWidget {
  final FilaBalance fila;
  final BalanceService svc;
  const _FilaWidget({super.key, required this.fila, required this.svc});

  @override
  Widget build(BuildContext context) {
    final item = fila.item;
    final dif = fila.diferencia;
    final Color colorDif = dif == null || dif.abs() < 1e-9
        ? AppColors.primario
        : (dif < 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706));

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: fila.invalida ? const Color(0xFFFEF2F2) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.detalle, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Sistema: ${fmtNum(item.cantidadSistema)} ${item.unidad}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: fila.texto,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (t) => svc.escribir(fila, t),
                    decoration: InputDecoration(
                      hintText: 'Cantidad real',
                      isDense: true,
                      errorText: fila.invalida ? 'Número inválido' : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (fila.unidadesPosibles.length > 1)
                  DropdownButton<String>(
                    value: fila.unidadEntrada,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final u in fila.unidadesPosibles)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (u) => u == null ? null : svc.cambiarUnidad(fila, u),
                  )
                else
                  Text(item.unidad, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            if (dif != null && !fila.invalida)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  dif.abs() < 1e-9
                      ? 'Coincide con el sistema.'
                      : 'Diferencia: ${dif > 0 ? '+' : ''}${fmtNum(dif, decimales: 3)} ${item.unidad}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorDif),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmarDialog extends StatefulWidget {
  final int contados;
  final int diferencias;
  const _ConfirmarDialog({required this.contados, required this.diferencias});

  @override
  State<_ConfirmarDialog> createState() => _ConfirmarDialogState();
}

class _ConfirmarDialogState extends State<_ConfirmarDialog> {
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Guardar balance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Se registrarán ${widget.contados} conteos, '
              '${widget.diferencias} con diferencia contra el sistema. '
              'Las diferencias quedan como ajustes.'),
          const SizedBox(height: 12),
          TextField(
            controller: _nota,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _nota.text), child: const Text('Guardar')),
      ],
    );
  }
}
