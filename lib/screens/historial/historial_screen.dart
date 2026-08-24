import 'package:flutter/material.dart';
import '../../services/bitacora_service.dart';
import '../../utils/formatters.dart';

/// Bitácora completa: "qué usuario entra y qué hace" (acciones) y el
/// log aparte de todo lo eliminado lógicamente (nunca se borra nada).
/// Visible solo para Almacén y Gerente.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});
  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _acciones = [];
  List<Map<String, dynamic>> _eliminaciones = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final acciones = await BitacoraService.historialAcciones();
    final eliminaciones = await BitacoraService.historialEliminaciones();
    if (!mounted) return;
    setState(() {
      _acciones = acciones;
      _eliminaciones = eliminaciones;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historial y Bitácora',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Acciones de usuarios'),
              Tab(text: 'Eliminaciones lógicas'),
            ],
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [_listaAcciones(), _listaEliminaciones()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _listaAcciones() {
    if (_acciones.isEmpty) {
      return const Center(child: Text('Sin registros todavía.'));
    }
    return ListView.separated(
      itemCount: _acciones.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = _acciones[i];
        final usr = a['usuarios'];
        return ListTile(
          leading: const Icon(Icons.circle, size: 10),
          title: Text(
              '${usr?['nombre_completo'] ?? 'Usuario'} — ${a['accion']}'),
          subtitle: Text(
              '${a['tabla_afectada'] ?? ''} ${a['dispositivo'] != null ? '· ${a['dispositivo']}' : ''}'),
          trailing: Text(fmtFechaHora(DateTime.tryParse(a['created_at'] ?? ''))),
        );
      },
    );
  }

  Widget _listaEliminaciones() {
    if (_eliminaciones.isEmpty) {
      return const Center(child: Text('No hay eliminaciones registradas.'));
    }
    return ListView.separated(
      itemCount: _eliminaciones.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _eliminaciones[i];
        final usr = e['usuarios'];
        final snap = e['snapshot'];
        return ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: Text('${snap?['detalle'] ?? snap?['codigo'] ?? 'Registro'} '
              '(${e['tabla_afectada']})'),
          subtitle: Text(
              'Eliminado por ${usr?['nombre_completo'] ?? '-'}${e['motivo'] != null ? ' · ${e['motivo']}' : ''}'),
          trailing: Text(fmtFechaHora(DateTime.tryParse(e['created_at'] ?? ''))),
        );
      },
    );
  }
}
