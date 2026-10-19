import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/widgets/dialog_banner.dart';

void main() {
  testWidgets(
      'lo que cuelga debajo del degradado se puede tocar '
      '(el botón de la cámara de "Mi perfil")', (tester) async {
    var tocado = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          DialogBanner(
            onCerrar: () {},
            // Como el avatar de "Mi perfil": 92 px, con el botón abajo a la
            // derecha — la parte que queda por debajo del degradado.
            child: SizedBox(
              width: 92,
              height: 92,
              child: Align(
                alignment: Alignment.bottomRight,
                child: IconButton(
                  key: const Key('camara'),
                  icon: const Icon(Icons.camera_alt, size: 14),
                  onPressed: () => tocado = true,
                ),
              ),
            ),
          ),
        ]),
      ),
    ));

    final boton = tester.getRect(find.byKey(const Key('camara')));
    final banner = tester.getRect(find.byType(DialogBanner));
    // El botón está en la franja que sobresale del degradado (110 px)...
    expect(boton.center.dy - banner.top, greaterThan(110));
    // ...y aun así recibe el toque.
    await tester.tap(find.byKey(const Key('camara')));
    expect(tocado, isTrue);
  });
}
