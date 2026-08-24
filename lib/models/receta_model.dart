/// Catálogo de recetas por sabor de gaseosa.
///
/// IMPORTANTE: las cantidades por unidad son valores de referencia
/// (placeholder) para que el cálculo automático funcione de inmediato.
/// Deben ajustarse con la ficha técnica real de cada sabor antes de usarse
/// en producción (Configuración > Recetas, o editando este archivo).
///
/// `insumoClave` se usa para *buscar* el insumo real dentro del inventario
/// (comparación por texto, sin distinguir mayúsculas/minúsculas), así que
/// no depende de IDs fijos y sigue funcionando aunque cambie el UUID.
class RecetaProducto {
  final String producto;
  final Map<String, double> insumosPorUnidad; // insumoClave -> cantidad/unidad

  const RecetaProducto({
    required this.producto,
    required this.insumosPorUnidad,
  });
}

class RecetaCatalogo {
  static const List<RecetaProducto> recetas = [
    RecetaProducto(
      producto: 'Naranja',
      insumosPorUnidad: {
        'Concentrado Salvietti Naranja': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Citrato de Sodio': 0.0008,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Lima Limón',
      insumosPorUnidad: {
        'Concentrado Salvietti Lima Limon': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.002,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Piña o Anana',
      insumosPorUnidad: {
        'Concentrado Salvietti Piña': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Granadina',
      insumosPorUnidad: {
        'Concentrado Salvietti Granadina': 0.012,
        'Azucar': 0.045,
        'Color Caramelo': 0.0006,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Pomelo',
      insumosPorUnidad: {
        'Concentrado Salvietti Pomelo': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Ginger Ale',
      insumosPorUnidad: {
        'Concentrado Salvietti Ginger Ale': 0.012,
        'Azucar': 0.045,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Kinoto Chepe',
      insumosPorUnidad: {
        'Concentrado Salvietti Kinoto Chepe': 0.012,
        'Azucar': 0.045,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Kinoto Cola',
      insumosPorUnidad: {
        'Concentrado Salvietti Kinoto Cola': 0.012,
        'Azucar': 0.045,
        'Cafeina': 0.0002,
        'Color Caramelo': 0.0006,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Papaya',
      insumosPorUnidad: {
        'Concentrado Salvietti Papaya': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Arándano',
      insumosPorUnidad: {
        'Concentrado Salvietti Arandano': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Frambuesa',
      insumosPorUnidad: {
        'Concentrado Salvietti Frambuesa': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Kiwi',
      insumosPorUnidad: {
        'Concentrado Kiwi': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Tumbo',
      insumosPorUnidad: {
        'Concentrado de Tumbo': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
    RecetaProducto(
      producto: 'Frutilla',
      insumosPorUnidad: {
        'Concentrado Frutilla': 0.012,
        'Azucar': 0.045,
        'Acido Citrico': 0.0015,
        'Preforma': 1,
        'Tapa Corona': 1,
      },
    ),
  ];
}
