import 'dart:io';

import 'package:arrow_ops/core/database/app_database.dart';
import 'package:arrow_ops/core/database/database_path_config.dart';
import 'package:arrow_ops/features/item/data/item_repository.dart';
import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late ItemRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('arrow_ops_item_category_test_db_');
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(tempDir.path);
    repository = const ItemRepository();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('stellt standardkategorien bereit', () async {
    final categories = await repository.getItemCategories();
    final names = categories.map((row) => row.name).toSet();

    expect(names.contains('Nocks'), isTrue);
    expect(names.contains('Schaefte'), isTrue);
    expect(names.contains('Spitzen'), isTrue);
    expect(names.contains('Werkzeuge'), isTrue);
  });

  test('propagiert umbenennung und loeschung auf artikelkategorien', () async {
    final nextCategoryId = await repository.nextItemCategoryId();
    await repository.saveItemCategory(
      ItemCategoryRow(icatId: nextCategoryId, name: 'Tests'),
    );

    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 1,
        icIdi: 'ART-1',
        category: 'Tests',
      ),
    );

    await repository.saveItemCategory(
      ItemCategoryRow(icatId: nextCategoryId, name: 'Tests Neu'),
    );

    var items = await repository.getCatalogueItems();
    expect(items.single.category, 'Tests Neu');

    await repository.deleteItemCategory(nextCategoryId);

    items = await repository.getCatalogueItems();
    expect(items.single.category, '');
  });

  test('legt unbekannte artikelkategorie beim speichern automatisch an', () async {
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 11,
        icIdi: 'ART-11',
        category: 'Nicht vorhanden',
      ),
    );

    final categories = await repository.getItemCategories();
    final names = categories.map((row) => row.name).toSet();
    expect(names.contains('Nicht vorhanden'), isTrue);

    final items = await repository.getCatalogueItems();
    expect(items.singleWhere((item) => item.icId == 11).category, 'Nicht vorhanden');
  });
}
