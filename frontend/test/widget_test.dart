import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmatod/main.dart';

void main() {
  testWidgets('HomeScreen muestra el buscador y el aviso legal', (tester) async {
    await tester.pumpWidget(const FarmaTodApp());

    expect(find.text('FarmaTod'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Buscar'), findsOneWidget);
    expect(
      find.textContaining('Requiere validación farmacéutica'),
      findsOneWidget,
    );
  });
}
