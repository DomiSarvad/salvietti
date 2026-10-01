import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../utils/notificaciones.dart';
import '../models/permisos_modelos.dart';
import '../repositories/permisos_repository.dart';
import '../services/permisos_gestion_service.dart';

/// Permisos por rol: qué puede ver/crear/editar/eliminar/aprobar cada rol
/// en cada módulo. Solo Gerente, y solo se llega acá desde Usuarios (al
/// editar o dar de alta a alguien, junto al campo de Rol) — no tiene un
/// ítem propio en el menú. Cada casilla se guarda sola al tocarla (sin
/// botón "Guardar") — la RLS de `permisos_rol` y su trigger de protección
/// son quienes realmente deciden qué se puede.
class PermisosScreen extends StatelessWidget {
  /// Con qué rol abre ya seleccionado (ej. el del usuario que se estaba
  /// editando). Null = Gerente, por defecto.
  final String? rolInicial;
  const PermisosScreen({super.key, this.rolInicial});

  @override
  Widget build(BuildContext context) {
    final usuario = context.read<AuthService>().usuarioActual!;
    return ChangeNotifierProvider(
      create: (_) => PermisosGestionService(SupabasePermisosRepository(), usuario,
          rolInicial: rolInicial)
        ..iniciar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatelessWidget {
  const _Vista();

  Future<void> _alternar(BuildContext context, PermisosGestionService svc, String modulo, String accion) async {
    final error = await svc.alternar(modulo, accion);
    if (error != null && context.mounted) mostrarError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<PermisosGestionService>();

    if (svc.cargando) return const Center(child: CircularProgressIndicator());
    if (!svc.puedeVer) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Solo el Gerente puede ver esta pantalla.'),
        ),
      );
    }
    if (svc.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: svc.iniciar, child: const Text('Reintentar')),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text('Permisos por rol', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Qué puede hacer cada rol en cada módulo. Los cambios se guardan solos, al tocar la '
            'casilla — no hay un botón "Guardar" aparte.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in Rol.todos)
              ChoiceChip(
                label: Text(Rol.etiqueta(r)),
                selected: r == svc.rolSeleccionado,
                selectedColor: AppColors.primario,
                labelStyle: TextStyle(
                    color: r == svc.rolSeleccionado ? Colors.white : Colors.black87, fontSize: 12),
                onSelected: (_) => svc.elegirRol(r),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!svc.puedeEditar)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8), borderRadius: BorderRadius.circular(10)),
            child: const Text('Podés ver los permisos, pero no editarlos.',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A6D1E))),
          ),
        Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE3E7EB))),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 44,
              columns: [
                const DataColumn(label: Text('Módulo')),
                for (final a in accionesPosibles) DataColumn(label: Text(etiquetaAccion(a))),
              ],
              rows: [for (final m in svc.modulos) _fila(context, svc, m)],
            ),
          ),
        ),
      ],
    );
  }

  DataRow _fila(BuildContext context, PermisosGestionService svc, ModuloApp m) {
    return DataRow(cells: [
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(m.nombre, overflow: TextOverflow.ellipsis, maxLines: 2),
      )),
      for (final a in accionesPosibles)
        DataCell(Checkbox(
          value: svc.tiene(m.id, a),
          onChanged: (svc.puedeEditar && !svc.guardando.contains('${m.id}:$a'))
              ? (_) => _alternar(context, svc, m.id, a)
              : null,
        )),
    ]);
  }
}
