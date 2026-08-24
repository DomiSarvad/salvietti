import 'package:flutter/material.dart';

import '../models/insumo_model.dart';
import '../models/usuario_model.dart';
import '../services/database_service.dart';
import '../services/hive_service.dart';
import '../services/inventario_logic_service.dart';
import 'componentes/formulario_consumo.widget.dart';
import 'componentes/formulario_salida.widget.dart';
import 'login_screen.dart';
import 'componentes/formulario_entrada.widget.dart';
import 'componentes/formulario_proveedor.widget.dart';
import 'componentes/grafico_consumo.widget.dart';
import 'componentes/historial_widget.dart';
import 'componentes/plan_produccion.widget.dart';
import 'componentes/tabla_inventario.widget.dart';
import 'componentes/tarjeta_insumo.widget.dart';

enum _VistaPanel { dashboard, inventario, tendencias, auditoria }

class InventarioScreen extends StatefulWidget {
  final UsuarioModel usuario;

  const InventarioScreen({super.key, required this.usuario});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  late Future<List<InsumoModel>> _insumosFuture;
  late Future<int> _pendingEntradasFuture;
  late Future<List<double>> _consumoSemanalFuture;
  final ValueNotifier<bool> _isOffline = ValueNotifier<bool>(false);
  bool _isSyncing = false;
  late UsuarioModel _usuarioActual;
  _VistaPanel _vista = _VistaPanel.dashboard;

  @override
  void initState() {
    super.initState();
    _usuarioActual = widget.usuario;
    _refreshData();
  }

  void _refreshData() {
    _insumosFuture = DatabaseService.fetchInsumos();
    _pendingEntradasFuture = HiveService.getPendingEntradasCount();
    _consumoSemanalFuture = DatabaseService.fetchConsumoSemanal();
  }

  Future<void> _sincronizarPendientes() async {
    if (!mounted) return;
    setState(() => _isSyncing = true);

    try {
      await DatabaseService.sincronizarPendientes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronización completada'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _refreshData();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de sincronización: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  bool get _puedeEliminar => DatabaseService.puedeEliminar(_usuarioActual.rol);

  bool get _puedeGestionarInventario => const {
        'encargado_almacen',
        'gerente',
        'jefe_produccion',
      }.contains(_usuarioActual.rol.toLowerCase());

  bool get _puedeVerJarabes => const {
        'encargado_jarabes',
        'gerente',
        'jefe_produccion',
      }.contains(_usuarioActual.rol.toLowerCase());

  Color get _statusColor =>
      _isOffline.value ? Colors.orange.shade700 : Colors.green.shade700;
  String get _statusLabel =>
      _isOffline.value ? 'OFFLINE - MODO LOCAL' : 'ONLINE';

  Future<void> _abrirFormularioEntrada() async {
    await showDialog(
      context: context,
      builder: (_) => FormularioEntradaInsumo(usuario: _usuarioActual),
    );
    if (mounted) {
      setState(() => _refreshData());
    }
  }

  Future<void> _abrirFormularioSalida() async {
    await showDialog(
      context: context,
      builder: (_) => FormularioSalidaInsumo(usuario: _usuarioActual),
    );
    if (mounted) {
      setState(() => _refreshData());
    }
  }

  Future<void> _abrirFormularioConsumo() async {
    await showDialog(
      context: context,
      builder: (_) => FormularioConsumoPlanta(usuario: _usuarioActual),
    );
    if (mounted) {
      setState(() => _refreshData());
    }
  }

  Future<void> _abrirFormularioProveedor() async {
    await showDialog(
      context: context,
      builder: (_) => FormularioProveedor(usuario: _usuarioActual),
    );
    if (mounted) {
      setState(() => _refreshData());
    }
  }

  Future<void> _abrirPlanProduccion() async {
    await showDialog(
      context: context,
      builder: (_) => PlanProduccionWidget(usuario: _usuarioActual),
    );
    if (mounted) {
      setState(() => _refreshData());
    }
  }

  Future<void> _mostrarBitacora() async {
    final resumen = await DatabaseService.fetchInsumos();
    final criticos = resumen.where((insumo) => insumo.esCritico).length;
    final observacion = resumen.where((insumo) => insumo.enObservacion).length;
    final pendientes = await _pendingEntradasFuture;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bitácora rápida'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Usuario: ${_usuarioActual.nombre}'),
              const SizedBox(height: 8),
              Text('Rol: ${_usuarioActual.rol}'),
              const SizedBox(height: 12),
              _InfoRow(label: 'Inventario crítico', value: '$criticos'),
              _InfoRow(label: 'En observación', value: '$observacion'),
              _InfoRow(
                label: 'Pendientes online',
                value: '$pendientes',
              ),
              const SizedBox(height: 12),
              const Text(
                'Toda acción queda registrada en la bitácora y se sincroniza con Supabase cuando haya conexión.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarBorradoLogico(
    String insumoId,
    String nombreInsumo,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrado lógico'),
        content: Text(
          '¿Desea desactivar $nombreInsumo sin eliminar físicamente el registro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      final ok = await DatabaseService.softDeleteInsumo(
        insumoId: insumoId,
        usuarioId: widget.usuario.id,
        motivo: 'Borrado lógico por $nombreInsumo',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Insumo desactivado correctamente.'
                : 'Se registró la acción en modo offline.',
          ),
          backgroundColor: ok ? Colors.green : Colors.orange,
        ),
      );
      _refreshData();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo realizar el borrado lógico: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _mostrarAlertas() async {
    final insumos = await _insumosFuture;
    final criticos = insumos.where((i) => i.activo && i.esCritico).toList();
    final observacion =
        insumos.where((i) => i.activo && i.enObservacion).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notificaciones de stock'),
        content: SizedBox(
          width: 460,
          child: (criticos.isEmpty && observacion.isEmpty)
              ? const Text('No hay alertas activas por el momento.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final insumo in criticos)
                        _AlertaTile(
                          color: Colors.red.shade700,
                          icon: Icons.error_outline,
                          texto: InventarioLogicService.textoAlerta(
                            insumo: insumo,
                            leadTime: 7,
                            porcentajeStockSeguridad: 0.10,
                          ),
                        ),
                      for (final insumo in observacion)
                        _AlertaTile(
                          color: Colors.orange.shade700,
                          icon: Icons.warning_amber_outlined,
                          texto: InventarioLogicService.textoAlerta(
                            insumo: insumo,
                            leadTime: 7,
                            porcentajeStockSeguridad: 0.10,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          if (criticos.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _vista = _VistaPanel.inventario);
              },
              child: const Text('Ver inventario'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarPerfil() async {
    final nombreController = TextEditingController(text: _usuarioActual.nombre);
    final emailController = TextEditingController(text: _usuarioActual.email);
    final telefonoController = TextEditingController(
      text: _usuarioActual.telefono ?? '',
    );
    final fotoController = TextEditingController(
      text: _usuarioActual.fotoUrl ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final avatarUrl = fotoController.text.trim();
            return AlertDialog(
              title: const Text('Mi perfil'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: Colors.green.shade700,
                        backgroundImage: avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                _usuarioActual.nombre
                                    .split(' ')
                                    .take(2)
                                    .map((e) => e[0])
                                    .join()
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 24,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nombreController,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Correo'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: telefonoController,
                      decoration: const InputDecoration(labelText: 'Teléfono'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: fotoController,
                      decoration: const InputDecoration(
                        labelText: 'URL de la foto',
                        hintText: 'https://...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context, false);
                    _cerrarSesion();
                  },
                  icon: const Icon(Icons.logout_outlined),
                  label: const Text('Cerrar sesión'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _usuarioActual = _usuarioActual.copyWith(
                        nombre: nombreController.text.trim().isNotEmpty
                            ? nombreController.text.trim()
                            : _usuarioActual.nombre,
                        email: emailController.text.trim().isNotEmpty
                            ? emailController.text.trim()
                            : _usuarioActual.email,
                        telefono: telefonoController.text.trim(),
                        fotoUrl: fotoController.text.trim(),
                      );
                    });
                    Navigator.pop(context, true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _cerrarSesion() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildAppBar() {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Salvietti',
            style: TextStyle(
              color: Colors.green.shade900,
              fontWeight: FontWeight.bold,
              fontSize: isDesktop ? 22 : 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Monitoreo de insumos y consumo proyectado',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: isDesktop ? 12 : 11,
            ),
          ),
        ],
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: _isOffline,
          builder: (context, isOffline, child) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isOffline ? Colors.orange.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOffline ? Icons.cloud_off : Icons.cloud_done,
                    color: _statusColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabel,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        FutureBuilder<List<InsumoModel>>(
          future: _insumosFuture,
          builder: (context, snapshot) {
            final alertas = (snapshot.data ?? [])
                .where((i) => i.activo && (i.esCritico || i.enObservacion))
                .length;
            return IconButton(
              onPressed: _mostrarAlertas,
              icon: Badge(
                label: Text('$alertas'),
                isLabelVisible: alertas > 0,
                backgroundColor: Colors.red.shade700,
                child: Icon(
                  alertas > 0
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: Colors.grey.shade800,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        if (isDesktop)
          PopupMenuButton<String>(
            offset: const Offset(0, 48),
            onSelected: (value) {
              if (value == 'perfil') {
                _mostrarPerfil();
              } else if (value == 'logout') {
                _cerrarSesion();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'perfil',
                child: Row(
                  children: [
                    Icon(Icons.person_outline),
                    SizedBox(width: 8),
                    Text('Mi perfil'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_outlined),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.green.shade700,
                    backgroundImage: _usuarioActual.fotoUrl != null &&
                            _usuarioActual.fotoUrl!.trim().isNotEmpty
                        ? NetworkImage(_usuarioActual.fotoUrl!)
                        : null,
                    child: (_usuarioActual.fotoUrl == null ||
                            _usuarioActual.fotoUrl!.trim().isEmpty)
                        ? Text(
                            _usuarioActual.nombre
                                .split(' ')
                                .take(2)
                                .map((e) => e[0])
                                .join()
                                .toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _usuarioActual.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _usuarioActual.rol,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSideMenu() {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Panel',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 24),
          _MenuItem(
            icon: Icons.dashboard,
            label: 'Dashboard',
            selected: _vista == _VistaPanel.dashboard,
            onTap: () => setState(() => _vista = _VistaPanel.dashboard),
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: Icons.inventory_2_outlined,
            label: 'Stock Health',
            selected: _vista == _VistaPanel.inventario,
            onTap: () => setState(() => _vista = _VistaPanel.inventario),
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: Icons.trending_up,
            label: 'Tendencias',
            selected: _vista == _VistaPanel.tendencias,
            onTap: () => setState(() => _vista = _VistaPanel.tendencias),
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: Icons.receipt_long,
            label: 'Auditoría',
            selected: _vista == _VistaPanel.auditoria,
            onTap: () => setState(() => _vista = _VistaPanel.auditoria),
          ),
          const Spacer(),
          FutureBuilder<List<InsumoModel>>(
            future: _insumosFuture,
            builder: (context, snapshot) {
              final criticos = (snapshot.data ?? [])
                  .where((i) => i.activo && i.esCritico)
                  .toList();
              if (criticos.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Sin alertas críticas por ahora.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALERTAS CRÍTICAS (${criticos.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      criticos.take(3).map((e) => e.nombre).join(' • '),
                      style: const TextStyle(fontSize: 13),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          setState(() => _vista = _VistaPanel.inventario),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      ),
                      child: const Text('RESOLVER AHORA'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCentralPanel(List<InsumoModel> insumos) {
    if (_vista == _VistaPanel.auditoria) {
      return const HistorialWidget();
    }

    final tarjetas = insumos.where((item) => item.activo).where((item) {
      if (!_puedeVerJarabes && item.nombre.toLowerCase().contains('jarabe')) {
        return false;
      }
      return true;
    }).toList();
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final criticos = tarjetas.where((item) => item.esCritico).length;
    final observaciones = tarjetas.where((item) => item.enObservacion).length;

    final titulo = switch (_vista) {
      _VistaPanel.dashboard => 'Estado de Planta',
      _VistaPanel.inventario => 'Insumos y Stock',
      _VistaPanel.tendencias => 'Tendencias de Consumo',
      _VistaPanel.auditoria => 'Auditoría',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_puedeGestionarInventario)
              FilledButton.icon(
                onPressed: _abrirFormularioEntrada,
                icon: const Icon(Icons.add_box_rounded),
                label: const Text('Entrada'),
              ),
            if (_puedeGestionarInventario)
              FilledButton.icon(
                onPressed: _abrirFormularioSalida,
                icon: const Icon(Icons.output_rounded),
                label: const Text('Salida'),
              ),
            FilledButton.icon(
              onPressed: _abrirFormularioConsumo,
              icon: const Icon(Icons.local_shipping_rounded),
              label: const Text('Consumo'),
            ),
            if (_puedeGestionarInventario)
              FilledButton.icon(
                onPressed: _abrirPlanProduccion,
                icon: const Icon(Icons.precision_manufacturing_rounded),
                label: const Text('Producción'),
              ),
            if (_puedeGestionarInventario)
              FilledButton.icon(
                onPressed: _abrirFormularioProveedor,
                icon: const Icon(Icons.business_rounded),
                label: const Text('Proveedor'),
              ),
            FilledButton.icon(
              onPressed: _mostrarBitacora,
              icon: const Icon(Icons.history_edu_rounded),
              label: const Text('Bitácora'),
            ),
            FilledButton.icon(
              onPressed: _isSyncing ? null : _sincronizarPendientes,
              icon: const Icon(Icons.sync),
              label: Text(_isSyncing ? 'Sincronizando...' : 'Sincronizar'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Monitoreo de insumos y consumo proyectado • ${DateTime.now().day} ${_monthName(DateTime.now().month)} ${DateTime.now().year}',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 500
                ? (constraints.maxWidth - 32) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _ResumenCard(
                    label: 'Críticos',
                    valor: '$criticos',
                    color: Colors.red,
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _ResumenCard(
                    label: 'Observación',
                    valor: '$observaciones',
                    color: Colors.orange,
                    icon: Icons.visibility_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _ResumenCard(
                    label: 'Total insumos',
                    valor: '${tarjetas.length}',
                    color: Colors.green,
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (_vista == _VistaPanel.inventario)
          TablaInventarioWidget(
            insumos: tarjetas,
            canDelete: _puedeEliminar,
            onDelete: (insumo) =>
                _confirmarBorradoLogico(insumo.id, insumo.nombre),
          )
        else if (_vista == _VistaPanel.tendencias)
          _buildTendenciasPanel(tarjetas)
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: tarjetas
                .map(
                  (insumo) => SizedBox(
                    width: isDesktop ? 320 : double.infinity,
                    child: TarjetaInsumoWidget(
                      insumo: insumo,
                      canDelete: _puedeEliminar,
                      onDelete: _puedeEliminar
                          ? () => _confirmarBorradoLogico(
                                insumo.id,
                                insumo.nombre,
                              )
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildTendenciasPanel(List<InsumoModel> insumos) {
    final ranking = [...insumos]..sort(
        (a, b) => b.consumoDiarioPromedio.compareTo(a.consumoDiarioPromedio),
      );
    final top = ranking.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Insumos con mayor rotación (consumo promedio diario)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (top.isEmpty)
            const Text('No hay datos de consumo disponibles todavía.')
          else
            ...top.map((insumo) {
              final maxConsumo = top.first.consumoDiarioPromedio <= 0
                  ? 1.0
                  : top.first.consumoDiarioPromedio;
              final proporcion =
                  (insumo.consumoDiarioPromedio / maxConsumo).clamp(0.0, 1.0);
              final color = switch (insumo.nivelStock) {
                StockNivel.critico => Colors.red.shade700,
                StockNivel.observacion => Colors.orange.shade700,
                StockNivel.seguro => Colors.green.shade700,
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            insumo.nombre,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${insumo.consumoDiarioPromedio.toStringAsFixed(1)} ${insumo.unidadMedida}/día',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: proporcion,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRightPanel(List<double> valores) {
    const eficiencia = 94.2;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          GraficoConsumoWidget(valores: valores),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EFICIENCIA',
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${eficiencia.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.show_chart_outlined,
                size: 40,
                color: Colors.green.shade700,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(92),
        child: _buildAppBar(),
      ),
      body: FutureBuilder<List<InsumoModel>>(
        future: _insumosFuture,
        builder: (context, snapshot) {
          final insumos = snapshot.data ?? [];

          final content = Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 24 : 16,
              16,
              isDesktop ? 24 : 16,
              16,
            ),
            child: Column(
              children: [
                Expanded(
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSideMenu(),
                            const SizedBox(width: 16),
                            Expanded(child: _buildCentralPanel(insumos)),
                            const SizedBox(width: 16),
                            FutureBuilder<List<double>>(
                              future: _consumoSemanalFuture,
                              builder: (context, chartSnapshot) {
                                final valores = chartSnapshot.data ??
                                    [3.0, 5.2, 4.5, 6.0, 4.8, 5.0, 3.3];
                                return SizedBox(
                                  width: 420,
                                  child: _buildRightPanel(valores),
                                );
                              },
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCentralPanel(insumos),
                              const SizedBox(height: 18),
                              FutureBuilder<List<double>>(
                                future: _consumoSemanalFuture,
                                builder: (context, chartSnapshot) {
                                  final valores = chartSnapshot.data ??
                                      [3.0, 5.2, 4.5, 6.0, 4.8, 5.0, 3.3];
                                  return _buildRightPanel(valores);
                                },
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<int>(
                  future: _pendingEntradasFuture,
                  builder: (context, pendingSnapshot) {
                    final pendientes = pendingSnapshot.data ?? 0;
                    return Align(
                      alignment:
                          isDesktop ? Alignment.centerRight : Alignment.center,
                      child: Text(
                        '${_statusLabel == 'OFFLINE - MODO LOCAL' ? 'Modo Off-line activo' : 'Conexión Online estable'} • Pendientes: $pendientes',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    );
                  },
                ),
              ],
            ),
          );

          return content;
        },
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: selected ? Colors.green.shade700 : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black87,
        elevation: selected ? 2 : 0,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
    );
  }
}

class _ResumenCard extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;
  final IconData icon;

  const _ResumenCard({
    required this.label,
    required this.valor,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
          );
          final iconWidget = CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          );

          if (constraints.maxWidth < 140) {
            return Column(
              children: [iconWidget, const SizedBox(height: 8), details],
            );
          }

          return Row(
            children: [
              iconWidget,
              const SizedBox(width: 12),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _AlertaTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String texto;

  const _AlertaTile({
    required this.color,
    required this.icon,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: color.withValues(alpha: 0.95)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
