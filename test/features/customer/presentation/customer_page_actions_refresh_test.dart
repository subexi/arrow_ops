import 'package:arrow_ops/features/customer/presentation/widgets/customer_page_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Aktualisieren ruft onRefresh genau einmal auf', (tester) async {
    var refreshCount = 0;

    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerPageActions(
            loading: false,
            databasePath: '/tmp/arrow_ops.db',
            searchController: controller,
            searchFocusNode: focusNode,
            onSearchChanged: (_) {},
            onCreateCustomer: () {},
            onRefresh: () {
              refreshCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aktualisieren'));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('Aktualisieren ist deaktiviert wenn loading true ist', (tester) async {
    var refreshCount = 0;

    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerPageActions(
            loading: true,
            databasePath: '/tmp/arrow_ops.db',
            searchController: controller,
            searchFocusNode: focusNode,
            onSearchChanged: (_) {},
            onCreateCustomer: () {},
            onRefresh: () {
              refreshCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aktualisieren'));
    await tester.pump();

    expect(refreshCount, 0);
  });
}
