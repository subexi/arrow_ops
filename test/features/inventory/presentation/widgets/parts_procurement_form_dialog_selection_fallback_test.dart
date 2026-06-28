import 'package:arrow_ops/features/inventory/domain/parts_procurement_models.dart';
import 'package:arrow_ops/features/inventory/presentation/widgets/parts_procurement_form_dialog.dart';
import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DialogHarness extends StatefulWidget {
  const _DialogHarness({required this.catalogueItems});

  final List<ItemCatalogueRow> catalogueItems;

  @override
  State<_DialogHarness> createState() => _DialogHarnessState();
}

class _DialogHarnessState extends State<_DialogHarness> {
  PartsProcurementRow? _result;

  Future<void> _openDialog() async {
    final result = await showDialog<PartsProcurementRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PartsProcurementFormDialog(
        nextId: 1,
        catalogueItems: widget.catalogueItems,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _openDialog,
              child: const Text('Dialog oeffnen'),
            ),
            Text('result_ppi=${_result?.ppIdi}'),
            Text('result_desc=${_result?.ppDescriptionDeLong}'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('auswahl nutzt ic_ide wenn ic_idi leer ist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DialogHarness(
          catalogueItems: const [
            ItemCatalogueRow(
              icId: 1,
              icIdi: 'ALT-1',
              icDescriptionDeLong: 'Alter Artikel',
            ),
            ItemCatalogueRow(
              icId: 106,
              icIde: 'ART-106',
              icDescriptionDeLong: 'Neuer Artikel',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pp_article_selector_tap')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ART-106').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('result_ppi=ART-106'), findsOneWidget);
    expect(find.text('result_desc=Neuer Artikel'), findsOneWidget);
  });

  testWidgets('auswahl faellt auf ic_id zurueck wenn ic_idi und ic_ide leer sind', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DialogHarness(
          catalogueItems: const [
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'ALT-2',
              icDescriptionDeLong: 'Alter Artikel 2',
            ),
            ItemCatalogueRow(
              icId: 205,
              icDescriptionDeLong: 'Artikel Ohne Kennung',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pp_article_selector_tap')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#205').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('result_ppi=205'), findsOneWidget);
    expect(find.text('result_desc=Artikel Ohne Kennung'), findsOneWidget);
  });

  testWidgets('artikelsuche filtert die auswahlliste', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DialogHarness(
          catalogueItems: const [
            ItemCatalogueRow(
              icId: 1,
              icIdi: 'ALT-1',
              icDescriptionDeLong: 'Alter Artikel',
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'ABC-2',
              icDescriptionDeLong: 'Anderer Artikel',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pp_article_selector_tap')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Artikel suchen'), 'ABC');
    await tester.pumpAndSettle();

    expect(find.text('ABC-2'), findsAtLeastNWidgets(1));
    expect(find.text('ALT-1'), findsNothing);
  });

  testWidgets('artikelsuche ohne treffer zeigt platzhalter im dropdown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DialogHarness(
          catalogueItems: const [
            ItemCatalogueRow(
              icId: 1,
              icIdi: 'ALT-1',
              icDescriptionDeLong: 'Alter Artikel',
            ),
            ItemCatalogueRow(
              icId: 2,
              icIdi: 'ABC-2',
              icDescriptionDeLong: 'Anderer Artikel',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pp_article_selector_tap')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Artikel suchen'), 'ZZZ');
    await tester.pumpAndSettle();

    final pickerDialog = find.widgetWithText(AlertDialog, 'Artikel auswählen');
    expect(
      find.descendant(of: pickerDialog, matching: find.text('Keine Treffer')),
      findsOneWidget,
    );
    expect(find.descendant(of: pickerDialog, matching: find.text('ALT-1')), findsNothing);
    expect(find.descendant(of: pickerDialog, matching: find.text('ABC-2')), findsNothing);
  });
}
