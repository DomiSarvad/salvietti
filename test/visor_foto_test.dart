import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvietti_control/shared/visor_foto.dart';

// PNG transparente de 1×1, para no depender de la red.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('abre la foto agrandada y se cierra con la X', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                mostrarFotoAmpliada(context, imagen: MemoryImage(_png), titulo: 'Gerente General'),
            child: const Text('ver'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ver'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget); // se puede hacer zoom
    expect(find.text('Gerente General'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
