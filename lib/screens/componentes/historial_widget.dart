import 'package:flutter/material.dart';

import '../../models/bitacora_entry.dart';
import '../../services/database_service.dart';

class HistorialWidget extends StatefulWidget {
  const HistorialWidget({super.key});

  @override
  State<HistorialWidget> createState() => _HistorialWidgetState();
}

class _HistorialWidgetState extends State<HistorialWidget> {
  late Future<List<BitacoraEntry>> _future;
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.fetchBitacora();
  }

  Future<void> _refrescar() async {
    setState(() {
      _future = DatabaseService.fetchBitacora();
    });
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BitacoraEntry>>(
      future: _future,
      builder: (context, snapshot) {
        final registros = snapshot.data ?? [];
        final cargando = snapshot.connectionState == ConnectionState.waiting;
        final hoy = DateTime.now();

        final ingresosHoy = registros
            .where(
              (r) =>
                  r.esIngreso &&
                  r.timestamp.year == hoy.year &&
                  r.timestamp.month == hoy.month &&
                  r.timestamp.day == hoy.day,
            )
            .length;
        final salidasHoy = registros
            .where(
              (r) =>
                  r.esSalida &&
                  r.timestamp.year == hoy.year &&
                  r.timestamp.month == hoy.month &&
                  r.timestamp.day == hoy.day,
            )
            .length;
        final pendientes = registros.where((r) => !r.sincronizado).length;

        final texto = _busqueda.trim().toLowerCase();
        final filtrados = texto.isEmpty
            ? registros
            : registros
                  .where(
                    (r) =>
                        r.insumoNombre.toLowerCase().contains(texto) ||
                        r.usuarioNombre.toLowerCase().contains(texto) ||
                        r.evento.toLowerCase().contains(texto),
                  )
                  .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Historial de Transacciones',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: cargando ? null : _refrescar,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Monitorea cada entrada y salida registrada en la bitácora de auditoría.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            if (cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LinearProgressIndicator(),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _kpiCard(
                  'Ingresos hoy',
                  '$ingresosHoy',
                  Icons.arrow_downward_rounded,
                  Colors.green,
                ),
                _kpiCard(
                  'Salidas hoy',
                  '$salidasHoy',
                  Icons.arrow_upward_rounded,
                  Colors.red,
                ),
                _kpiCard(
                  'Pendientes de sync',
                  '$pendientes',
                  Icons.sync_problem_rounded,
                  Colors.orange,
                ),
                _kpiCard(
                  'Total de eventos',
                  '${registros.length}',
                  Icons.receipt_long_rounded,
                  Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _busquedaController,
                      onChanged: (value) => setState(() => _busqueda = value),
                      decoration: InputDecoration(
                        hintText: 'Buscar por insumo, usuario o evento...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!cargando && filtrados.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'Aún no hay movimientos registrados en la bitácora.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.grey.shade50,
                        ),
                        columnSpacing: 28,
                        columns: const [
                          DataColumn(label: Text('FECHA / HORA')),
                          DataColumn(label: Text('USUARIO')),
                          DataColumn(label: Text('ACCIÓN')),
                          DataColumn(label: Text('ÍTEM')),
                          DataColumn(label: Text('CANTIDAD'), numeric: true),
                          DataColumn(label: Text('SYNC')),
                        ],
                        rows: filtrados.map((registro) {
                          final f = registro.timestamp;
                          final fechaTexto =
                              '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')} '
                              '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
                          final colorAccion = registro.esIngreso
                              ? Colors.green.shade700
                              : registro.esSalida
                              ? Colors.red.shade700
                              : Colors.blueGrey;
                          return DataRow(
                            cells: [
                              DataCell(Text(fechaTexto)),
                              DataCell(Text(registro.usuarioNombre)),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorAccion.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    registro.tipo.toUpperCase(),
                                    style: TextStyle(
                                      color: colorAccion,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(Text(registro.insumoNombre)),
                              DataCell(
                                Text(registro.cantidad.toStringAsFixed(1)),
                              ),
                              DataCell(
                                Icon(
                                  registro.sincronizado
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  size: 18,
                                  color: registro.sincronizado
                                      ? Colors.green.shade600
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, String valor, IconData icon, Color color) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
