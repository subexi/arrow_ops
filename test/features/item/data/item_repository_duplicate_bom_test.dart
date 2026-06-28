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

  test('summiert BOM-Komponentengewichte und schreibt sie in den Parent-Artikel', () async {
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 2,
        icIdi: 'COMP-002',
        icDescriptionDeLong: 'Komponente 2',
        icWeight: 2.5,
        icPurchasePriceNet: 2.0,
      ),
    );

    final bomRows = await repository.getBomItems();
    final root = bomRows.firstWhere(
      (row) => row.ibItemId == 10 && row.ibParentId == null,
    );

    await repository.saveBomItem(
      ItemBomRow(
        ibItemId: 2,
        ibParentId: root.ibId,
        ibQuantity: 2,
      ),
    );

    final catalogueRows = await repository.getCatalogueItems();
    final rootArticle = catalogueRows.firstWhere((row) => row.icId == 10);

    // 1x COMP-001 (0g) + 2x COMP-002 (2.5g) = 5.0g
    expect(rootArticle.icWeight, closeTo(5.0, 0.000001));
  });

  test('propagiert abgeleitete Gewichte rekursiv ueber Zwischenbaugruppen', () async {
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 102,
        icIdi: 'COMP-102',
        icDescriptionDeLong: 'Komponente 102',
        icWeight: 6.4,
        icPurchasePriceNet: 1.0,
      ),
    );
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 104,
        icIdi: 'COMP-104',
        icDescriptionDeLong: 'Komponente 104',
        icWeight: 7.6,
        icPurchasePriceNet: 1.0,
      ),
    );
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 103,
        icIdi: 'SUB-103',
        icDescriptionDeLong: 'Zwischenbaugruppe 103',
        icWeight: 0.0,
        icPurchasePriceNet: 1.0,
      ),
    );
    await repository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 106,
        icIdi: 'ROOT-106',
        icDescriptionDeLong: 'Endbaugruppe 106',
        icWeight: 0.0,
        icPurchasePriceNet: 1.0,
      ),
    );

    await repository.saveBomItem(
      const ItemBomRow(
        ibItemId: 103,
        ibParentId: null,
        ibQuantity: 1,
      ),
    );
    final bomRowsAfter103Root = await repository.getBomItems();
    final root103 = bomRowsAfter103Root.firstWhere(
      (row) => row.ibItemId == 103 && row.ibParentId == null,
    );
    await repository.saveBomItem(
      ItemBomRow(
        ibItemId: 102,
        ibParentId: root103.ibId,
        ibQuantity: 1,
      ),
    );
    await repository.saveBomItem(
      ItemBomRow(
        ibItemId: 104,
        ibParentId: root103.ibId,
        ibQuantity: 1,
      ),
    );

    await repository.saveBomItem(
      const ItemBomRow(
        ibItemId: 106,
        ibParentId: null,
        ibQuantity: 1,
      ),
    );
    final bomRowsAfter106Root = await repository.getBomItems();
    final root106 = bomRowsAfter106Root.firstWhere(
      (row) => row.ibItemId == 106 && row.ibParentId == null,
    );
    await repository.saveBomItem(
      ItemBomRow(
        ibItemId: 103,
        ibParentId: root106.ibId,
        ibQuantity: 1,
      ),
    );

    final catalogueRows = await repository.getCatalogueItems();
    final subAssembly = catalogueRows.firstWhere((row) => row.icId == 103);
    final finalAssembly = catalogueRows.firstWhere((row) => row.icId == 106);

    expect(subAssembly.icWeight, closeTo(14.0, 0.000001));
    expect(finalAssembly.icWeight, closeTo(14.0, 0.000001));
  });
}
