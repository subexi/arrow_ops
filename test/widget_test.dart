import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Customer title is visible', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('Arrow Ops - Customer'),
        ),
      ),
    );

    expect(find.text('Arrow Ops - Customer'), findsOneWidget);
  });
}
