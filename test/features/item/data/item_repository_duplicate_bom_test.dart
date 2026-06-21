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
    tempDir = await Directory.systemTemp.createTemp('arrow_ops_item_repo_test_db_');
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(tempDir.path);
    repository = const ItemRepository();

    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 1,
        icIdi: 'COMP-001',
        icDescriptionDeLong: 'Komponente',
        icPurchasePriceNet: 1.0,
      ),
    );
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 10,
        icIdi: 'ROOT-010',
        icDescriptionDeLong: 'Rootartikel',
        icPurchasePriceNet: 5.0,
      ),
    );

    await repository.saveBomItem(
      const ItemBomRow(
        ibItemId: 10,
        ibParentId: null,
        ibQuantity: 1,
      ),
    );

    final bomRows = await repository.getBomItems();
    final root = bomRows.firstWhere(
      (row) => row.ibItemId == 10 && row.ibParentId == null,
    );

    await repository.saveBomItem(
      ItemBomRow(
        ibItemId: 1,
        ibParentId: root.ibId,
        ibQuantity: 1,
      ),
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('dupliziert keine Komponentenzuordnungen in fremde BOMs', () async {
    final result = await repository.duplicateCatalogueItemWithBom(1, includeBom: true);

    expect(result.duplicatedAnchorRows, 0);
    expect(result.duplicatedBomRows, 0);

    final bomRows = await repository.getBomItems();
    final duplicatedLinks = bomRows.where((row) => row.ibItemId == result.newCatalogueId).toList();
    expect(duplicatedLinks, isEmpty);

    final originalLinks = bomRows.where((row) => row.ibItemId == 1).toList();
    expect(originalLinks.length, 1);
  });
}
