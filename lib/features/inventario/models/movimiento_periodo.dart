/// Cuánto entró y cuánto salió de un ítem (en un almacén) en un período,
/// para el filtro Desde/Hasta de Almacenes. Los ajustes suman a entradas o
/// a salidas según su signo.
class MovimientoPeriodo {
  final double entradas;
  final double salidas;
  const MovimientoPeriodo({this.entradas = 0, this.salidas = 0});

  MovimientoPeriodo sumar(double cantidad) => cantidad >= 0
      ? MovimientoPeriodo(entradas: entradas + cantidad, salidas: salidas)
      : MovimientoPeriodo(entradas: entradas, salidas: salidas - cantidad);
}
