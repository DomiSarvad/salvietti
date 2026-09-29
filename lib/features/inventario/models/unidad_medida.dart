/// Unidades de medida del inventario (coinciden con el check de `inv_items`).
class UnidadMedida {
  static const todas = ['KG', 'GR', 'PZA', 'UNI', 'L', 'ML', 'CJA', 'M'];

  static String etiqueta(String u) {
    switch (u) {
      case 'KG':
        return 'Kilogramos (KG)';
      case 'GR':
        return 'Gramos (GR)';
      case 'PZA':
        return 'Piezas (PZA)';
      case 'UNI':
        return 'Unidades (UNI)';
      case 'L':
        return 'Litros (L)';
      case 'ML':
        return 'Mililitros (ML)';
      case 'CJA':
        return 'Cajas (CJA)';
      case 'M':
        return 'Metros (M)';
      default:
        return u;
    }
  }

  /// Convierte [valor] entre gramos/kilos y mililitros/litros; las demás
  /// unidades no se convierten (devuelve el mismo valor).
  static double convertir(double valor, {required String de, required String a}) {
    if (de == a) return valor;
    if (de == 'GR' && a == 'KG') return valor / 1000;
    if (de == 'KG' && a == 'GR') return valor * 1000;
    if (de == 'ML' && a == 'L') return valor / 1000;
    if (de == 'L' && a == 'ML') return valor * 1000;
    return valor;
  }
}
