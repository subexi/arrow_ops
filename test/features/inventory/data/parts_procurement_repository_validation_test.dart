import 'dart:io';

import 'package:arrow_ops/core/database/app_database.dart';
import 'package:arrow_ops/core/database/database_path_config.dart';
import 'package:arrow_ops/features/inventory/data/parts_procurement_repository.dart';
import 'package:arrow_ops/features/inventory/domain/parts_procurement_models.dart';
import 'package:arrow_ops/features/item/data/item_repository.dart';
import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late ItemRepository itemRepository;
  late PartsProcurementRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('arrow_ops_inventory_repo_test_db_');
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(tempDir.path);

    itemRepository = const ItemRepository();
    repository = const PartsProcurementRepository();

    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 101,
        icIdi: 'ART-IDI-101',
        icIde: 'ART-IDE-101',
        icDescriptionDeLong: 'Artikel 101',
      ),
    );

    await itemRepository.saveCatalogueItem(
      const ItemCatalogueRow(
        icId: 205,
        icDescriptionDeLong: 'Artikel 205 ohne Kennung',
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

  PartsProcurementRow buildRow({required int id, required String token}) {
    return PartsProcurementRow(
      ppId: id,
      ppIdi: token,
      ppPurchaseDate: '2026-06-28',
      ppQuantity: 2,
      ppPriceNet: 12.5,
      ppTotalPriceNet: 25,
      ppDescriptionDeLong: 'Testbestand',
    );
  }

  test('akzeptiert pp_idi wenn ic_idi passt', () async {
    await repository.save(buildRow(id: 1, token: 'ART-IDI-101'));

    final rows = await repository.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.ppIdi, 'ART-IDI-101');
  });

  test('akzeptiert pp_idi wenn ic_ide passt', () async {
    await repository.save(buildRow(id: 2, token: 'ART-IDE-101'));

    final rows = await repository.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.ppIdi, 'ART-IDE-101');
  });

  test('akzeptiert pp_idi wenn numerische ic_id als Text passt', () async {
    await repository.save(buildRow(id: 3, token: '205'));

    final rows = await repository.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.ppIdi, '205');
  });

  test('wirft Fehler fuer unbekannten Artikel-Token', () async {
    expect(
      () => repository.save(buildRow(id: 4, token: 'NICHT-VORHANDEN')),
      throwsA(isA<Exception>()),
    );
  });
}
