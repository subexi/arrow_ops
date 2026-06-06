import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester, {
    required List<ItemBomRow> initialBomItems,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: const TextScaler.linear(0.7)),
            child: child!,
          );
        },
        home: ItemCataloguePage(
          loadOnInit: false,
          initialCatalogueItems: const [
            ItemCatalogueRow(
              icId: 1,
              icIdi: 'Root Artikel',
              icPriceNet: 10,
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'Kind Artikel',
              icPriceNet: 5,
            ),
            ItemCatalogueRow(
              icId: 3,
              icIdi: 'Neues Kind',
              icPriceNet: 3,
            ),
          ],
          initialBomItems: initialBomItems,
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> openBomAction(WidgetTester tester, String actionLabel) async {
    final directButton = find.widgetWithText(OutlinedButton, actionLabel);
    if (directButton.evaluate().isNotEmpty) {
      await tester.tap(directButton);
      await tester.pumpAndSettle();
      return;
    }

    await tester.tap(find.byTooltip('BOM Aktionen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(actionLabel).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Neu unter markiertem uebernimmt markierten BOM-Eintrag als Parent', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(
      tester,
      initialBomItems: const [
        ItemBomRow(
          ibId: 10,
          ibItemId: 1,
          ibParentId: null,
          ibQuantity: 1,
        ),
        ItemBomRow(
          ibId: 11,
          ibItemId: 2,
          ibParentId: 10,
          ibQuantity: 1,
        ),
      ],
    );

    // Sichtbarer BOM-Eintrag ist das Kind (#11), diesen als Parent markieren.
    await tester.tap(find.text('11').first);
    await tester.pumpAndSettle();

    await openBomAction(tester, 'Neu unter markiertem');

    expect(find.text('BOM-Eintrag anlegen'), findsOneWidget);
    expect(find.textContaining('Ausgewaehlter Parent: 2 • Kind Artikel'), findsOneWidget);
  });

  testWidgets('Neu verwendet beim ersten Kind den erzeugten Root-Parent statt Root/null', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(
      tester,
      initialBomItems: const [],
    );

    await openBomAction(tester, 'Neu');

    expect(find.text('BOM-Eintrag anlegen'), findsOneWidget);
    expect(find.textContaining('Ausgewaehlter Parent: 1 • Root Artikel'), findsOneWidget);
  });

  testWidgets('Neu nutzt Root-Parent auch wenn ein Kind in der BOM markiert ist', (tester) async {
    addTearDown(() async {
      await binding.setSurfaceSize(null);
    });

    await pumpPage(
      tester,
      initialBomItems: const [
        ItemBomRow(
          ibId: 10,
          ibItemId: 1,
          ibParentId: null,
          ibQuantity: 1,
        ),
        ItemBomRow(
          ibId: 11,
          ibItemId: 2,
          ibParentId: 10,
          ibQuantity: 1,
        ),
      ],
    );

    await tester.tap(find.text('11').first);
    await tester.pumpAndSettle();

    await openBomAction(tester, 'Neu');

    expect(find.text('BOM-Eintrag anlegen'), findsOneWidget);
    expect(find.textContaining('Ausgewaehlter Parent: 1 • Root Artikel'), findsOneWidget);
  });
}
