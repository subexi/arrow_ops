import 'package:arrow_ops/features/order/presentation/order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('doppelklick auf HTS code ruft callback auf', (tester) async {
    var doubleTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: HtsCodeCellContent(
              code: '99887766',
              onOpen: () {},
              onDoubleTap: () => doubleTapCount++,
            ),
          ),
        ),
      ),
    );

    final htsTextFinder = find.text('99887766');
    expect(htsTextFinder, findsOneWidget);

    await tester.tap(htsTextFinder);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(htsTextFinder);
    await tester.pump(const Duration(milliseconds: 150));

    expect(doubleTapCount, 1);
  });

  testWidgets('HTS code ist selektierbar und hat Oeffnen-Icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: HtsCodeCellContent(
              code: '99887766',
              onOpen: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });
}

void _noop() {}
