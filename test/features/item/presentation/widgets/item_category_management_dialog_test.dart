import 'package:arrow_ops/features/item/data/item_repository.dart';
import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/item/presentation/widgets/item_category_management_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeItemRepository extends ItemRepository {
  _FakeItemRepository({List<ItemCategoryRow> initial = const []})
      : _categories = List<ItemCategoryRow>.from(initial);

  final List<ItemCategoryRow> _categories;

  @override
  Future<List<ItemCategoryRow>> getItemCategories() async {
    final sorted = List<ItemCategoryRow>.from(_categories)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  @override
  Future<int> nextItemCategoryId() async {
    if (_categories.isEmpty) {
      return 1;
    }
    return _categories.map((e) => e.icatId).reduce((a, b) => a > b ? a : b) + 1;
  }

  @override
  Future<void> saveItemCategory(ItemCategoryRow category) async {
    final name = category.name.trim();
    if (name.isEmpty) {
      throw Exception('Kategorie darf nicht leer sein.');
    }

    final duplicate = _categories.any(
      (row) => row.icatId != category.icatId && row.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw Exception('Kategorie existiert bereits.');
    }

    final index = _categories.indexWhere((row) => row.icatId == category.icatId);
    final normalized = category.copyWith(name: name);
    if (index >= 0) {
      _categories[index] = normalized;
    } else {
      _categories.add(normalized);
    }
  }

  @override
  Future<void> deleteItemCategory(int categoryId) async {
    _categories.removeWhere((row) => row.icatId == categoryId);
  }
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({required this.repository});

  final _FakeItemRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => ItemCategoryManagementDialog(repository: repository),
            );
          },
          child: const Text('Dialog oeffnen'),
        ),
      ),
    );
  }
}

void main() {
  late _FakeItemRepository repository;

  setUp(() async {
    repository = _FakeItemRepository();
  });

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 100,
    Duration step = const Duration(milliseconds: 50),
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }

    fail('Widget nicht gefunden: $finder');
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _DialogHarness(repository: repository),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await pumpUntilFound(tester, find.text('Kategorien verwalten'));
    await pumpUntilFound(tester, find.text('Kategorie anlegen'));

    expect(find.text('Kategorien verwalten'), findsOneWidget);
  }

  Future<void> tapWhenVisible(
    WidgetTester tester,
    Finder finder,
  ) async {
    await pumpUntilFound(tester, finder);
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('kann kategorie anlegen und bearbeiten', (tester) async {
    await openDialog(tester);

    await tapWhenVisible(tester, find.text('Kategorie anlegen'));
    await pumpUntilFound(tester, find.text('Kategorie anlegen'));

    await tester.enterText(find.widgetWithText(TextField, 'Kategorie'), 'Test Kategorie');
    final createDialog = find.byType(AlertDialog).last;
    await tapWhenVisible(
      tester,
      find.descendant(of: createDialog, matching: find.text('Speichern')),
    );
    await pumpUntilFound(tester, find.text('Test Kategorie'));

    final tile = find.ancestor(
      of: find.text('Test Kategorie'),
      matching: find.byType(ListTile),
    );
    expect(tile, findsOneWidget);
    await tapWhenVisible(
      tester,
      find.descendant(of: tile, matching: find.byTooltip('Bearbeiten')),
    );
    await pumpUntilFound(tester, find.text('Kategorie bearbeiten'));

    await tester.enterText(find.widgetWithText(TextField, 'Kategorie'), 'Test Kategorie Neu');
    final editDialog = find.byType(AlertDialog).last;
    await tapWhenVisible(
      tester,
      find.descendant(of: editDialog, matching: find.text('Speichern')),
    );
    await pumpUntilFound(tester, find.text('Test Kategorie Neu'));

    final updatedTile = find.ancestor(
      of: find.text('Test Kategorie Neu'),
      matching: find.byType(ListTile),
    );
    expect(updatedTile, findsOneWidget);
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Test Kategorie')),
      findsNothing,
    );
  });

  testWidgets('kann kategorie loeschen', (tester) async {
    await repository.saveItemCategory(
      ItemCategoryRow(
        icatId: await repository.nextItemCategoryId(),
        name: 'Loesch Mich',
      ),
    );

    await openDialog(tester);
    expect(find.text('Loesch Mich'), findsOneWidget);

    final tile = find.ancestor(
      of: find.text('Loesch Mich'),
      matching: find.byType(ListTile),
    );
    await tapWhenVisible(
      tester,
      find.descendant(of: tile, matching: find.byTooltip('Loeschen')),
    );
    await pumpUntilFound(tester, find.text('Kategorie loeschen?'));

    expect(find.text('Kategorie loeschen?'), findsOneWidget);
    final deleteDialog = find.byType(AlertDialog).last;
    await tapWhenVisible(
      tester,
      find.descendant(of: deleteDialog, matching: find.text('Loeschen')),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Loesch Mich'), findsNothing);
  });
}
