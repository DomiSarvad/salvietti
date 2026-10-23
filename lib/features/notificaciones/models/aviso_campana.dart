/// Una fila del panel de la campana: un tipo de cosa pendiente, cuántas hay y
/// a qué pantalla lleva tocarla.
class AvisoCampana {
  final String id; // ej. 'compras_por_aprobar'
  final String titulo;
  final String detalle;
  final int cantidad;
  final String ruta; // ruta de HomeShell
  final String icono; // nombre; la pantalla lo traduce a IconData

  /// Las respuestas se pueden marcar como vistas (dejan de contar); lo que
  /// está para resolver cuenta hasta que se resuelve.
  final bool seMarcaVisto;

  const AvisoCampana({
    required this.id,
    required this.titulo,
    required this.detalle,
    required this.cantidad,
    required this.ruta,
    required this.icono,
    this.seMarcaVisto = false,
  });
}

/// Algo propio que ya tuvo respuesta (aprobado/rechazado): se avisa una vez.
class RespuestaPropia {
  final String clave; // 'solicitud:12', 'compra:7'
  final String tipo; // 'solicitud' | 'compra'
  const RespuestaPropia(this.clave, this.tipo);
}
