import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../core/constants.dart';

/// Un paso de un tour de ayuda: qué parte de la pantalla señalar (con su
/// [GlobalKey]) y qué explicarle a quien recién entra sobre esa parte.
class PasoAyuda {
  final GlobalKey clave;
  final String titulo;
  final String texto;
  final ShapeLightFocus forma;
  const PasoAyuda({
    required this.clave,
    required this.titulo,
    required this.texto,
    this.forma = ShapeLightFocus.RRect,
  });

  /// Envuelve [child] con la clave de este paso (para el recorrido) Y un
  /// `Tooltip` con el mismo título/texto: al pasar el mouse por encima (o
  /// mantener presionado en el celular) se puede volver a leer la
  /// explicación puntual de esa parte sin tener que repetir el recorrido
  /// completo desde el botón "?".
  Widget envolver(Widget child) => KeyedSubtree(
        key: clave,
        child: Tooltip(
          waitDuration: const Duration(milliseconds: 500),
          textAlign: TextAlign.start,
          richMessage: TextSpan(
            children: [
              TextSpan(text: '$titulo\n', style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: texto),
            ],
          ),
          child: child,
        ),
      );
}

/// Tours de ayuda "con lo básico": unos globitos que señalan lo principal
/// de una pantalla, con "Siguiente"/"Saltar". Se recuerda qué tour ya se
/// vio (`HiveBoxes.preferencias`, guardado por dispositivo — no por
/// usuario, porque en la fábrica suele ser la misma compu para varios
/// turnos), así no aparece de nuevo solo cada vez que se entra; el botón
/// "?" del encabezado lo puede volver a mostrar cuando haga falta.
class TourAyuda {
  static Box get _caja => Hive.box(HiveBoxes.preferencias);

  static bool yaVisto(String idTour) =>
      (_caja.get('tour_$idTour') as bool?) ?? false;

  static Future<void> _marcarVisto(String idTour) => _caja.put('tour_$idTour', true);

  /// Reinicia todos los tours (por si alguien quiere volver a verlos todos
  /// desde cero) — no se usa todavía en ninguna pantalla, queda disponible.
  static Future<void> reiniciarTodos() async {
    final claves = _caja.keys.where((k) => k.toString().startsWith('tour_')).toList();
    for (final k in claves) {
      await _caja.delete(k);
    }
  }

  /// Muestra el tour. Con [soloSiNoVisto] en true (el auto-arranque al
  /// entrar a la pantalla) no hace nada si ya se vio antes; el botón "?"
  /// de cada pantalla lo llama con `soloSiNoVisto: false` para repetirlo
  /// las veces que haga falta.
  static void mostrar(
    BuildContext context, {
    required String idTour,
    required List<PasoAyuda> pasos,
    bool soloSiNoVisto = false,
  }) {
    if (soloSiNoVisto && yaVisto(idTour)) return;
    // Los GlobalKey de pasos que no están montados en este momento (ej. una
    // tarjeta que no se muestra porque el rol no tiene ese permiso) no
    // tienen contexto todavía: se descartan en vez de romper el tour.
    final pasosVisibles =
        pasos.where((p) => p.clave.currentContext != null).toList();
    if (pasosVisibles.isEmpty) return;

    final tamanoPantalla = MediaQuery.of(context).size;

    final targets = [
      for (final p in pasosVisibles)
        TargetFocus(
          identify: p.titulo,
          keyTarget: p.clave,
          shape: p.forma,
          radius: 10,
          contents: [
            TargetContent(
              // Si el objetivo está en la mitad de abajo de la pantalla, el
              // globo se dibuja arriba (si no, queda pegado abajo, fuera de
              // lo visible, sin forma de bajar a verlo — el overlay del tour
              // no scrollea).
              align: _alineacion(p.clave, tamanoPantalla.height),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: tamanoPantalla.height * 0.6),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.titulo,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.primario)),
                        const SizedBox(height: 6),
                        Text(p.texto,
                            style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black87,
      textSkip: 'Saltar',
      // Antes de iluminar cada paso, lo trae a la vista scrolleando la
      // pantalla (o el diálogo) que lo contiene: si no, el globo señala algo
      // que puede estar fuera de lo visible, sin forma de bajar a verlo —
      // el overlay del tour en sí no scrollea solo.
      beforeFocus: (target) async {
        final ctx = target.keyTarget?.currentContext;
        if (ctx == null) return;
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      onFinish: () => _marcarVisto(idTour),
      onSkip: () {
        _marcarVisto(idTour);
        return true;
      },
    ).show(context: context);
  }

  static ContentAlign _alineacion(GlobalKey clave, double alturaPantalla) {
    final caja = clave.currentContext?.findRenderObject() as RenderBox?;
    if (caja == null || !caja.hasSize) return ContentAlign.bottom;
    final centroY = caja.localToGlobal(Offset.zero).dy + caja.size.height / 2;
    return centroY > alturaPantalla / 2 ? ContentAlign.top : ContentAlign.bottom;
  }
}

/// Botón "?" para el encabezado de una pantalla: repite el tour de ayuda
/// de esa pantalla en cualquier momento (no solo la primera vez).
class BotonAyuda extends StatelessWidget {
  final String idTour;
  final List<PasoAyuda> Function() pasos;
  const BotonAyuda({super.key, required this.idTour, required this.pasos});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Ayuda de esta pantalla',
      icon: const Icon(Icons.help_outline),
      onPressed: () =>
          TourAyuda.mostrar(context, idTour: idTour, pasos: pasos(), soloSiNoVisto: false),
    );
  }
}
