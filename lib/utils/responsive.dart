import 'package:flutter/widgets.dart';

/// Ancho seguro para el contenido de un diálogo (`AlertDialog`/`content:
/// SizedBox(width: ...)`): usa el ancho preferido en pantallas grandes,
/// pero nunca más de lo que entra en la pantalla actual — así ningún
/// diálogo se desborda al abrir la app en un celular o una ventana
/// angosta.
///
/// [margen] por defecto (128) = el padding que `AlertDialog` agrega
/// alrededor del contenido (24 de cada lado) más el margen que deja
/// contra el borde de la pantalla (40 de cada lado). Para un ancho fijo
/// que NO está dentro de un `AlertDialog` (ej. la tarjeta del login),
/// pasar un [margen] más chico (el padding real alrededor de ese widget).
double anchoDialogo(BuildContext context, double preferido, {double margen = 128}) {
  final disponible = MediaQuery.of(context).size.width - margen;
  if (disponible <= 0) return preferido;
  return preferido < disponible ? preferido : disponible;
}
