import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: const TextScaler.linear(0.7)),
            child: child!,
          );
        },
        home: const ItemCataloguePage(
          loadOnInit: false,
          initialCatalogueItems: [
            ItemCatalogueRow(
              icId: 1,
              icIdi: 'Artikel Z',
              icIdv: 'Z-Var',
              icPriceNet: 10,
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'Artikel A',
              icIdv: 'A-Var',
              icPriceNet: 20,
            ),
          ],
          initialBomItems: [],
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  double yOf(WidgetTester tester, String text) {
    return tester.getTopLeft(find.text(text).first).dy;
  }

  testWidgets('zeigt Spalte Variante und sortiert ueber den Header', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(tester);

    expect(find.text('Variante'), findsOneWidget);

    // Initial sort is by Artikel-ID ASC, so item #1 (Z-Var) appears before #2 (A-Var).
    expect(yOf(tester, 'Z-Var'), lessThan(yOf(tester, 'A-Var')));

    await tester.tap(find.text('Variante'));
    await tester.pumpAndSettle();

    // First tap sorts Variante ASC.
    expect(yOf(tester, 'A-Var'), lessThan(yOf(tester, 'Z-Var')));

    await tester.tap(find.text('Variante'));
    await tester.pumpAndSettle();

    // Second tap sorts Variante DESC.
    expect(yOf(tester, 'Z-Var'), lessThan(yOf(tester, 'A-Var')));
  });
}
