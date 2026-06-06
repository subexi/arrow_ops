import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/item/presentation/widgets/item_bom_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DialogHarness extends StatefulWidget {
  const _DialogHarness();

  @override
  State<_DialogHarness> createState() => _DialogHarnessState();
}

class _DialogHarnessState extends State<_DialogHarness> {
  ItemBomRow? _result;

  Future<void> _openDialog() async {
    final result = await showDialog<ItemBomRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemBomFormDialog(
        catalogueItems: const [
          ItemCatalogueRow(
            icId: 2,
            icIdi: 'Parent Artikel',
            icPriceNet: 10,
          ),
          ItemCatalogueRow(
            icId: 3,
            icIdi: 'Kind Artikel',
            icPriceNet: 5,
          ),
        ],
        availableBomItems: const [
          ItemBomRow(
            ibId: 10,
            ibItemId: 2,
            ibParentId: null,
            ibQuantity: 1,
          ),
        ],
        nextId: 99,
        initialParentId: 10,
        initialItemId: 3,
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
            Text('result_parent=${_result?.ibParentId}'),
            Text('result_item=${_result?.ibItemId}'),
          ],
        ),
      ),
    );
  }
}

class _DialogHarnessInvalidParent extends StatefulWidget {
  const _DialogHarnessInvalidParent();

  @override
  State<_DialogHarnessInvalidParent> createState() => _DialogHarnessInvalidParentState();
}

class _DialogHarnessInvalidParentState extends State<_DialogHarnessInvalidParent> {
  ItemBomRow? _result;

  Future<void> _openDialog() async {
    final result = await showDialog<ItemBomRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemBomFormDialog(
        catalogueItems: const [
          ItemCatalogueRow(
            icId: 2,
            icIdi: 'Parent Artikel',
            icPriceNet: 10,
          ),
          ItemCatalogueRow(
            icId: 3,
            icIdi: 'Kind Artikel',
            icPriceNet: 5,
          ),
        ],
        availableBomItems: const [
          ItemBomRow(
            ibId: 10,
            ibItemId: 2,
            ibParentId: null,
            ibQuantity: 1,
          ),
        ],
        nextId: 99,
        initialParentId: 74,
        initialItemId: 3,
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
            Text('result_parent=${_result?.ibParentId}'),
            Text('result_item=${_result?.ibItemId}'),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('uebernimmt initialen Parent beim Speichern des BOM-Eintrags', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _DialogHarness(),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    expect(find.text('BOM-Eintrag anlegen'), findsOneWidget);
    expect(find.textContaining('Ausgewaehlter Parent:'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('result_parent=10'), findsOneWidget);
    expect(find.text('result_item=3'), findsOneWidget);
  });

  testWidgets('faellt bei ungueltigem Parent auf gueltigen Parent zurueck ohne Warnhinweis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _DialogHarnessInvalidParent(),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    expect(find.text('BOM-Eintrag anlegen'), findsOneWidget);
    expect(find.textContaining('Hinweis: Parent #74 ist ungueltig'), findsNothing);
    expect(find.textContaining('Ausgewaehlter Parent: 2 • Parent Artikel'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('result_parent=10'), findsOneWidget);
    expect(find.text('result_item=3'), findsOneWidget);
  });
}
