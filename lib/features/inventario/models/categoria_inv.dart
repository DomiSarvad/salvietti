/// Nodo del árbol de categorías (PET › Tapas › Tapa Short › Negro).
class CategoriaInv {
  final int id;
  final int? padreId;
  final String nombre;
  final String almacenId;
  final int orden;
  const CategoriaInv({
    required this.id,
    required this.padreId,
    required this.nombre,
    required this.almacenId,
    this.orden = 0,
  });

  factory CategoriaInv.fromMap(Map<String, dynamic> m) => CategoriaInv(
        id: (m['id'] as num).toInt(),
        padreId: (m['padre_id'] as num?)?.toInt(),
        nombre: m['nombre'] as String,
        almacenId: m['almacen_id'] as String,
        orden: (m['orden'] as num?)?.toInt() ?? 0,
      );
}
