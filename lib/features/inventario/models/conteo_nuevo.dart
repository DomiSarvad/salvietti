/// Un conteo físico listo para guardar (ya en la unidad del ítem).
class ConteoNuevo {
  final int itemId;
  final String almacenId;
  final double cantidadReal;
  final String? observaciones;
  const ConteoNuevo({
    required this.itemId,
    required this.almacenId,
    required this.cantidadReal,
    this.observaciones,
  });

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'almacen_id': almacenId,
        'cantidad_real': cantidadReal,
        'observaciones': observaciones,
      };
}
