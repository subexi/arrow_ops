import 'package:arrow_ops/app/app_module.dart';
import 'package:arrow_ops/app/app_shell.dart';
import 'package:arrow_ops/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Orders module is accessible from Shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ArrowOpsTheme.light(),
        home: const ArrowOpsShell(
          initialModuleId: ArrowOpsModuleId.orders,
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify we're on the Orders page (look for a characteristic widget)
    expect(find.text('Aufträge'), findsWidgets);
  });
}
