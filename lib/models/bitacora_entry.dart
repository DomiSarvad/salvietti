class BitacoraEntry {
  final String id;
  final String usuarioId;
  final String usuarioNombre;
  final String evento;
  final String tipo;
  final String insumoNombre;
  final double cantidad;
  final DateTime timestamp;
  final bool sincronizado;

  BitacoraEntry({
    required this.id,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.evento,
    required this.tipo,
    required this.insumoNombre,
    required this.cantidad,
    required this.timestamp,
    required this.sincronizado,
  });

  factory BitacoraEntry.fromMap(
    Map<String, dynamic> map, {
    String? usuarioNombre,
  }) {
    DateTime parsedFecha;
    final rawFecha = map['timestamp'] ?? map['created_at'];
    parsedFecha = DateTime.tryParse(rawFecha?.toString() ?? '') ??
        DateTime.now();

    return BitacoraEntry(
      id: map['id']?.toString() ?? '',
      usuarioId: map['usuario_id']?.toString() ?? '',
      usuarioNombre: usuarioNombre ?? map['usuario_id']?.toString() ?? 'N/D',
      evento: map['evento']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'movimiento',
      insumoNombre: map['insumo_nombre']?.toString() ?? 'N/D',
      cantidad: (map['cantidad'] ?? 0).toDouble(),
      timestamp: parsedFecha,
      sincronizado: map['sincronizado'] == null
          ? true
          : (map['sincronizado'] == true ||
                map['sincronizado'].toString() == 'true'),
    );
  }

  bool get esIngreso => tipo.toLowerCase().contains('entrada') ||
      tipo.toLowerCase().contains('ingreso');

  bool get esSalida => tipo.toLowerCase().contains('salida') ||
      tipo.toLowerCase().contains('consumo');
}
