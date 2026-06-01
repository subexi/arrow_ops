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
              icIdi: 'Ohne Variante',
              icIdv: '-',
              icPriceNet: 10,
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'Mit Variante A',
              icIdv: 'A-1',
              icPriceNet: 20,
            ),
            ItemCatalogueRow(
              icId: 3,
              icIdi: 'Mit Variante B',
              icIdv: 'B-1',
              icPriceNet: 30,
            ),
          ],
          initialBomItems: [],
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('filtert Artikelkatalog nach Varianten und ohne Varianten', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(tester);

    expect(find.text('Ohne Variante'), findsOneWidget);
    expect(find.text('Mit Variante A'), findsOneWidget);
    expect(find.text('Mit Variante B'), findsOneWidget);

    if (find.byType(ExpansionTile).evaluate().isNotEmpty) {
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('variant-filter-with')));
    await tester.pumpAndSettle();

    expect(find.text('Ohne Variante'), findsNothing);
    expect(find.text('Mit Variante A'), findsOneWidget);
    expect(find.text('Mit Variante B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('variant-filter-without')));
    await tester.pumpAndSettle();

    expect(find.text('Ohne Variante'), findsOneWidget);
    expect(find.text('Mit Variante A'), findsNothing);
    expect(find.text('Mit Variante B'), findsNothing);
  });
}
