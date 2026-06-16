import 'package:arrow_ops/app/app_module.dart';
import 'package:arrow_ops/app/app_shell.dart';
import 'package:arrow_ops/app/app_theme.dart';
import 'package:arrow_ops/features/order/presentation/order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on the requested module', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ArrowOpsTheme.light(),
        home: const ArrowOpsShell(initialModuleId: ArrowOpsModuleId.orders),
      ),
    );

    expect(find.text('Aufträge'), findsWidgets);
    expect(find.byType(OrderPage), findsOneWidget);
  });
}
