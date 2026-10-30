import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Tema de toda la app. Los botones siguen el estilo de los de la barra
/// superior (sincronización, Configuración): esquinas de 12, un brillo
/// arriba y sombra suave que crece al pasar el mouse. Está en el tema, no en
/// cada pantalla, así un botón nuevo ya sale igual.
ThemeData temaApp() {
  const radio = BorderRadius.all(Radius.circular(12));
  const forma = RoundedRectangleBorder(borderRadius: radio);
  const borde = Color(0xFFD5DDE3);
  const texto = TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2);

  bool deshabilitado(Set<WidgetState> s) => s.contains(WidgetState.disabled);
  bool activo(Set<WidgetState> s) =>
      s.contains(WidgetState.hovered) || s.contains(WidgetState.focused);

  // Va ENCIMA del color de fondo (sea el verde, el rojo de "peligro" o el que
  // ponga la pantalla): claro arriba, apenas oscuro abajo = relieve.
  Widget brillo(BuildContext _, Set<WidgetState> s, Widget? child) => deshabilitado(s)
      ? child!
      : DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radio,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: activo(s) ? 0.24 : 0.16),
                Colors.white.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.10),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: child,
        );

  // Botón de color lleno (acción principal: "Nuevo ítem", "Guardar"…).
  final lleno = ButtonStyle(
    shape: const WidgetStatePropertyAll(forma),
    textStyle: const WidgetStatePropertyAll(texto),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
    elevation: WidgetStateProperty.resolveWith(
        (s) => deshabilitado(s) ? 0 : (activo(s) ? 6 : 3)),
    shadowColor: WidgetStatePropertyAll(AppColors.primario.withValues(alpha: 0.55)),
    backgroundBuilder: brillo,
  );

  return ThemeData(
    useMaterial3: true,
    // La incluida en assets/fonts (en la web no se baja de internet).
    fontFamily: 'Roboto',
    colorSchemeSeed: AppColors.primario,
    scaffoldBackgroundColor: AppColors.fondo,
    filledButtonTheme: FilledButtonThemeData(
      style: lleno.merge(FilledButton.styleFrom(backgroundColor: AppColors.primario)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: lleno.merge(ElevatedButton.styleFrom(
          backgroundColor: AppColors.primario, foregroundColor: Colors.white)),
    ),
    // Acción secundaria ("Balance", "Salida directa"): blanca con relieve,
    // el borde se vuelve verde al pasar el mouse.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(forma),
        textStyle: const WidgetStatePropertyAll(texto),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => deshabilitado(s) ? Colors.black38 : AppColors.primario),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => deshabilitado(s) ? const Color(0xFFF1F3F5) : Colors.white),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
            color: activo(s) ? AppColors.primario.withValues(alpha: 0.6) : borde)),
        elevation: WidgetStateProperty.resolveWith(
            (s) => deshabilitado(s) ? 0 : (activo(s) ? 4 : 1.5)),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.25)),
        backgroundBuilder: (_, s, child) => deshabilitado(s)
            ? child!
            : DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: radio,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Transparente: el fondo blanco y el efecto al tocar se ven a través.
                    colors: [Color(0x00000000), Color(0x0A1B5E3A)],
                  ),
                ),
                child: child,
              ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: forma,
        textStyle: texto,
        foregroundColor: AppColors.primario,
      ),
    ),
    // Filtros ("Tipo", "Pedido", migas de categorías).
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.primario.withValues(alpha: 0.14),
      side: const BorderSide(color: borde),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      labelStyle: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87),
      iconTheme: const IconThemeData(color: AppColors.primario, size: 16),
      elevation: 1,
      pressElevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primario,
      foregroundColor: Colors.white,
      elevation: 4,
      hoverElevation: 8,
      shape: CircleBorder(),
    ),
  );
}
