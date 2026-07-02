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
              category: 'Standard',
              icIdv: '-',
              icPriceNet: 10,
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'Mit Variante A',
              category: 'Premium',
              icIdv: 'A-1',
              icPriceNet: 20,
            ),
            ItemCatalogueRow(
              icId: 3,
              icIdi: 'Mit Variante B',
              category: 'Premium',
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

  testWidgets('filtert nach konkreter Variante und oeffnet Bearbeiten fuer gefilterten Eintrag', (
    tester,
  ) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(tester);

    if (find.byType(ExpansionTile).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('variant-value-filter')).evaluate().isEmpty) {
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
    }

    final variantValueFilter = find.byKey(const ValueKey('variant-value-filter'));
    expect(variantValueFilter, findsOneWidget);

    await tester.tap(variantValueFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A-1').last);
    await tester.pumpAndSettle();

    expect(find.text('Ohne Variante'), findsNothing);
    expect(find.text('Mit Variante A'), findsOneWidget);
    expect(find.text('Mit Variante B'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten').first);
    await tester.pumpAndSettle();

    expect(find.text('Katalogeintrag bearbeiten'), findsOneWidget);
  });

  testWidgets('filtert nach konkreter Kategorie und oeffnet Bearbeiten fuer gefilterten Eintrag', (
    tester,
  ) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(tester);

    if (find.byType(ExpansionTile).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('category-value-filter')).evaluate().isEmpty) {
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
    }

    final categoryValueFilter = find.byKey(const ValueKey('category-value-filter'));
    expect(categoryValueFilter, findsOneWidget);

    await tester.tap(categoryValueFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium').last);
    await tester.pumpAndSettle();

    expect(find.text('Ohne Variante'), findsNothing);
    expect(find.text('Mit Variante A'), findsOneWidget);
    expect(find.text('Mit Variante B'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten').first);
    await tester.pumpAndSettle();

    expect(find.text('Katalogeintrag bearbeiten'), findsOneWidget);
  });

  testWidgets('setzt Auswahl beim Kategorie-Filterwechsel auf ersten sichtbaren Artikel', (
    tester,
  ) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(tester);

    if (find.byType(ExpansionTile).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('category-value-filter')).evaluate().isEmpty) {
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
    }

    final varianteBFinder = find.text('Mit Variante B').first;
    await tester.ensureVisible(varianteBFinder);
    await tester.tap(varianteBFinder);
    await tester.pumpAndSettle();

    final categoryValueFilter = find.byKey(const ValueKey('category-value-filter'));
    expect(categoryValueFilter, findsOneWidget);

    await tester.tap(categoryValueFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten').first);
    await tester.pumpAndSettle();

    expect(find.text('Katalogeintrag bearbeiten'), findsOneWidget);
    final bezeichnungField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Bezeichnung'),
    );
    expect(bezeichnungField.controller?.text, 'Ohne Variante');
  });
}
