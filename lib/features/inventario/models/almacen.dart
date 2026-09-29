/// Un almacén con su propio stock: General, Jarabes o Soplado.
class Almacen {
  final String id; // 'general' | 'jarabes' | 'soplado'
  final String nombre;
  const Almacen({required this.id, required this.nombre});

  factory Almacen.fromMap(Map<String, dynamic> m) =>
      Almacen(id: m['id'] as String, nombre: m['nombre'] as String);
}
