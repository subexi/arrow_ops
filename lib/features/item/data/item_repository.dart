import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/item_purchase_price_calculator.dart';
import '../domain/item_models.dart';

class DuplicateCatalogueResult {
  const DuplicateCatalogueResult({
    required this.newCatalogueId,
    required this.duplicatedAnchorRows,
    required this.duplicatedBomRows,
  });

  final int newCatalogueId;
  final int duplicatedAnchorRows;
  final int duplicatedBomRows;
}

class ItemRepository {
  const ItemRepository();

  Future<void> syncDerivedPurchasePrices({Set<int> excludedArticleIds = const {}}) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _recalculatePurchasePricesInTransaction(
        txn,
        excludedArticleIds: excludedArticleIds,
      );
    });
  }

  Future<List<ItemCatalogueRow>> getCatalogueItems() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('item_catalogue', orderBy: 'ic_id ASC');
    return rows.map(ItemCatalogueRow.fromMap).toList();
  }

  Future<int> deleteOrphanBomItems({required Set<int> validCatalogueIds}) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final deleted = await _deleteOrphanBomItemsInTransaction(
        txn,
        validCatalogueIds: validCatalogueIds,
      );
      if (deleted > 0) {
        await _recalculatePurchasePricesInTransaction(txn);
      }
      return deleted;
    });
  }

  Future<int> deleteRootOnlyBomAnchors() async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      await _ensureBomIdsInTransaction(txn);
      final bomRows = await _fetchBomRows(txn);
      if (bomRows.isEmpty) {
        return 0;
      }

      final parentIds = bomRows.map((row) => row.ibParentId).whereType<int>().toSet();
      final rootOnlyIds = bomRows
          .where((row) => row.ibParentId == null)
          .map((row) => row.ibId)
          .whereType<int>()
          .where((id) => !parentIds.contains(id))
          .toList(growable: false);

      if (rootOnlyIds.isEmpty) {
        return 0;
      }

      await txn.delete(
        'item_bom',
        where: _whereInClause('ib_id', rootOnlyIds.length),
        whereArgs: rootOnlyIds,
      );

      final remaining = await _fetchBomRows(txn);
      await _writeBomRows(txn, _renumberBomRows(_groupBomRowsByParent(remaining)));
      await _recalculatePurchasePricesInTransaction(txn);
      return rootOnlyIds.length;
    });
  }

  Future<List<ItemBomRow>> getBomItems() async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _ensureBomIdsInTransaction(txn);
    });
    final rows = await db.query('item_bom', orderBy: 'COALESCE(ib_parent_id, -1) ASC, ib_order ASC, ib_id ASC');
    return rows.map(ItemBomRow.fromMap).toList();
  }

  Future<int> nextCatalogueId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('SELECT COALESCE(MAX(ic_id), 0) + 1 AS next_id FROM item_catalogue');
    return _readInt(rows.first['next_id']);
  }

  Future<int> nextBomId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('SELECT COALESCE(MAX(ib_id), 0) + 1 AS next_id FROM item_bom');
    return _readInt(rows.first['next_id']);
  }

  Future<int> nextBomOrder(int? parentId) async {
    final db = await AppDatabase.instance.database;
    final whereClause = parentId == null ? 'ib_parent_id IS NULL' : 'ib_parent_id = ?';
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(ib_order), 0) + 1 AS next_order FROM item_bom WHERE $whereClause',
      parentId == null ? const [] : [parentId],
    );
    return _readInt(rows.first['next_order']);
  }

  Future<void> saveCatalogueItem(ItemCatalogueRow item) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'item_catalogue',
        item.toMap(),
        where: 'ic_id = ?',
        whereArgs: [item.icId],
      );
      if (updated == 0) {
        await txn.insert('item_catalogue', item.toMap());
      }
    });

    await syncDerivedPurchasePrices(excludedArticleIds: {item.icId});
  }

  Future<DuplicateCatalogueResult> duplicateCatalogueItemWithBom(
    int sourceCatalogueId, {
    bool includeBom = true,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final sourceRows = await txn.query(
        'item_catalogue',
        where: 'ic_id = ?',
        whereArgs: [sourceCatalogueId],
        limit: 1,
      );
      if (sourceRows.isEmpty) {
        throw StateError('Katalogeintrag #$sourceCatalogueId nicht gefunden.');
      }

      final sourceItem = ItemCatalogueRow.fromMap(sourceRows.first);
      final maxIdRows = await txn.rawQuery('SELECT COALESCE(MAX(ic_id), 0) AS max_id FROM item_catalogue');
      final newCatalogueId = _readInt(maxIdRows.first['max_id']) + 1;

      final allNameRows = await txn.query('item_catalogue', columns: ['ic_idi']);
      final existingNamesLower = allNameRows
          .map((row) => row['ic_idi']?.toString().trim().toLowerCase() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();
      final duplicateName = _buildDuplicateCatalogueName(
        sourceName: sourceItem.icIdi,
        existingNamesLower: existingNamesLower,
      );

      final duplicateItem = sourceItem.copyWith(
        icId: newCatalogueId,
        icIdi: duplicateName,
      );
      await txn.insert('item_catalogue', duplicateItem.toMap());

      if (!includeBom) {
        return DuplicateCatalogueResult(
          newCatalogueId: newCatalogueId,
          duplicatedAnchorRows: 0,
          duplicatedBomRows: 0,
        );
      }

      await _ensureBomIdsInTransaction(txn);
      final bomRows = await _fetchBomRows(txn);

        final anchorRows = bomRows
          .where((row) => row.ibItemId == sourceCatalogueId && row.ibParentId == null)
          .toList(growable: false);
      if (anchorRows.isEmpty) {
        return DuplicateCatalogueResult(
          newCatalogueId: newCatalogueId,
          duplicatedAnchorRows: 0,
          duplicatedBomRows: 0,
        );
      }

      final anchorIds = anchorRows.map((row) => row.ibId).whereType<int>();
      final subtreeIds = _collectBomSubtreeIds(bomRows, anchorIds).toSet();
      final subtreeRows = bomRows
          .where((row) {
            final id = row.ibId;
            return id != null && subtreeIds.contains(id);
          })
          .toList(growable: false)
        ..sort((a, b) {
          final parentCompare = (a.ibParentId ?? -1).compareTo(b.ibParentId ?? -1);
          if (parentCompare != 0) {
            return parentCompare;
          }
          return _compareBomRows(a, b);
        });

      final maxBomId = bomRows.map((row) => row.ibId ?? 0).fold<int>(0, (maxValue, id) => id > maxValue ? id : maxValue);
      var nextBomId = maxBomId + 1;

      final nodeIdByParentAndItem = <String, int>{
        for (final row in bomRows)
          if (row.ibId != null) _bomLinkKey(row.ibParentId, row.ibItemId): row.ibId!,
      };

      final idMap = <int, int>{};
      for (final row in subtreeRows) {
        final oldId = row.ibId;
        if (oldId == null) {
          continue;
        }
        idMap[oldId] = nextBomId;
        nextBomId += 1;
      }

      var insertedRows = 0;
      for (final row in subtreeRows) {
        final oldId = row.ibId;
        if (oldId == null) {
          continue;
        }
        final oldParentId = row.ibParentId;
        final mappedParentId = oldParentId == null ? null : (idMap[oldParentId] ?? oldParentId);
        final mappedItemId = row.ibItemId == sourceCatalogueId ? newCatalogueId : row.ibItemId;
        final existingId = nodeIdByParentAndItem[_bomLinkKey(mappedParentId, mappedItemId)];
        if (existingId != null) {
          idMap[oldId] = existingId;
          continue;
        }
        final mappedId = idMap[oldId];
        if (mappedId == null) {
          continue;
        }
        final duplicateRow = row.copyWith(
          ibId: mappedId,
          ibParentId: mappedParentId,
          ibItemId: mappedItemId,
        );
        await txn.insert('item_bom', duplicateRow.toMap());
        nodeIdByParentAndItem[_bomLinkKey(mappedParentId, mappedItemId)] = mappedId;
        insertedRows += 1;
      }

      final updatedRows = await _fetchBomRows(txn);
      await _writeBomRows(txn, _renumberBomRows(_groupBomRowsByParent(updatedRows)));
      return DuplicateCatalogueResult(
        newCatalogueId: newCatalogueId,
        duplicatedAnchorRows: anchorRows.length,
        duplicatedBomRows: insertedRows,
      );
    });
  }

  Future<void> deleteCatalogueItem(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final bomRows = await _fetchBomRows(txn);
      final deletedBomIds = _collectBomSubtreeIds(
        bomRows,
        bomRows.where((row) => row.ibItemId == id).map((row) => row.ibId).whereType<int>(),
      );
      if (deletedBomIds.isNotEmpty) {
        await txn.delete(
          'item_bom',
          where: _whereInClause('ib_id', deletedBomIds.length),
          whereArgs: deletedBomIds,
        );
      }

      await txn.delete('item_catalogue', where: 'ic_id = ?', whereArgs: [id]);

      final remainingCatalogueRows = await txn.query('item_catalogue', columns: ['ic_id']);
      final validCatalogueIds = remainingCatalogueRows.map((row) => _readInt(row['ic_id'])).where((value) => value > 0).toSet();
      await _deleteOrphanBomItemsInTransaction(txn, validCatalogueIds: validCatalogueIds);

      final remainingBomRows = await _fetchBomRows(txn);
      await _writeBomRows(txn, _renumberBomRows(_groupBomRowsByParent(remainingBomRows)));
      await _recalculatePurchasePricesInTransaction(txn);
    });
  }

  Future<void> saveBomItem(ItemBomRow item) async {
    final db = await AppDatabase.instance.database;
    final id = item.ibId ?? await nextBomId();
    final order = item.ibOrder <= 0 ? await nextBomOrder(item.ibParentId) : item.ibOrder;
    final normalized = item.copyWith(ibId: id, ibOrder: order);

    await db.transaction((txn) async {
      final updated = await txn.update(
        'item_bom',
        normalized.toMap(),
        where: 'ib_id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        await txn.insert('item_bom', normalized.toMap());
      }
      await _recalculatePurchasePricesInTransaction(txn);
    });
  }

  Future<void> moveBomItem({
    required int itemId,
    required int? parentId,
  }) async {
    await reorderBomItem(itemId: itemId, newParentId: parentId);
  }

  Future<void> reorderBomItem({
    required int itemId,
    required int? newParentId,
    int? beforeItemId,
    int? afterItemId,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _ensureBomIdsInTransaction(txn);
      final rows = await _fetchBomRows(txn);
      final moved = rows.where((row) => row.ibId == itemId).cast<ItemBomRow?>().firstWhere((row) => row != null, orElse: () => null);
      if (moved == null) {
        return;
      }

      if (newParentId != null) {
        if (newParentId == itemId) {
          return;
        }

        final descendants = _collectBomSubtreeIds(rows, [itemId]);
        if (descendants.contains(newParentId)) {
          return;
        }
      }

      final targetParentId = newParentId;
      final remaining = [...rows]..removeWhere((row) => row.ibId == itemId);
      final grouped = _groupBomRowsByParent(remaining);
      final targetSiblings = List<ItemBomRow>.from(
        grouped[targetParentId] ?? const <ItemBomRow>[],
      )..sort(_compareBomRows);

      final insertIndex = _resolveInsertIndex(
        siblings: targetSiblings,
        beforeItemId: beforeItemId,
        afterItemId: afterItemId,
      );

      targetSiblings.insert(insertIndex, moved.copyWith(ibParentId: targetParentId));
      grouped[targetParentId] = targetSiblings;

      await _writeBomRows(txn, _renumberBomRows(grouped));
      await _recalculatePurchasePricesInTransaction(txn);
    });
  }

  Future<void> deleteBomItem(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final bomRows = await _fetchBomRows(txn);
      final deletedBomIds = _collectBomSubtreeIds(bomRows, [id]);
      if (deletedBomIds.isNotEmpty) {
        await txn.delete(
          'item_bom',
          where: _whereInClause('ib_id', deletedBomIds.length),
          whereArgs: deletedBomIds,
        );
      }

      final remaining = await _fetchBomRows(txn);
      await _writeBomRows(txn, _renumberBomRows(_groupBomRowsByParent(remaining)));
      await _recalculatePurchasePricesInTransaction(txn);
    });
  }

  Future<void> _recalculatePurchasePricesInTransaction(
    Transaction txn, {
    Set<int> excludedArticleIds = const {},
  }) async {
    await _ensureBomIdsInTransaction(txn);
    final catalogueRowsRaw = await txn.query('item_catalogue', orderBy: 'ic_id ASC');
    final catalogueRows = catalogueRowsRaw.map(ItemCatalogueRow.fromMap).toList(growable: false);
    if (catalogueRows.isEmpty) {
      return;
    }

    final bomRows = await _fetchBomRows(txn);
    if (bomRows.isEmpty) {
      return;
    }

    final derivedByArticleId = calculateDerivedPurchasePrices(
      catalogueRows: catalogueRows,
      bomRows: bomRows,
    );

    if (derivedByArticleId.isEmpty) {
      return;
    }

    final catalogueById = {
      for (final row in catalogueRows) row.icId: row,
    };

    for (final entry in derivedByArticleId.entries) {
      final articleId = entry.key;
      if (excludedArticleIds.contains(articleId)) {
        // Den gerade manuell gespeicherten Artikel nicht sofort wieder ueberschreiben.
        continue;
      }
      final derivedValue = entry.value;
      final current = catalogueById[articleId];
      if (current == null) {
        continue;
      }

      if ((current.icPurchasePriceNet - derivedValue).abs() < 0.000001) {
        continue;
      }

      await txn.update(
        'item_catalogue',
        {'ic_purchase_price_net': derivedValue},
        where: 'ic_id = ?',
        whereArgs: [articleId],
      );
    }
  }

  Future<List<ItemBomRow>> _fetchBomRows(Transaction txn) async {
    final rows = await txn.query('item_bom', orderBy: 'COALESCE(ib_parent_id, -1) ASC, ib_order ASC, ib_id ASC');
    return rows.map(ItemBomRow.fromMap).toList();
  }

  Map<int?, List<ItemBomRow>> _groupBomRowsByParent(List<ItemBomRow> rows) {
    final grouped = <int?, List<ItemBomRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.ibParentId, () => []).add(row);
    }
    return grouped;
  }

  List<ItemBomRow> _renumberBomRows(Map<int?, List<ItemBomRow>> grouped) {
    final result = <ItemBomRow>[];
    for (final entry in grouped.entries) {
      final siblings = entry.value;
      for (var i = 0; i < siblings.length; i++) {
        result.add(siblings[i].copyWith(ibOrder: i + 1));
      }
    }
    return result;
  }

  int _resolveInsertIndex({
    required List<ItemBomRow> siblings,
    int? beforeItemId,
    int? afterItemId,
  }) {
    if (beforeItemId != null) {
      final beforeIndex = siblings.indexWhere((row) => row.ibId == beforeItemId);
      if (beforeIndex >= 0) {
        return beforeIndex;
      }
    }

    if (afterItemId != null) {
      final afterIndex = siblings.indexWhere((row) => row.ibId == afterItemId);
      if (afterIndex >= 0) {
        return afterIndex + 1;
      }
    }

    return siblings.length;
  }

  Future<void> _writeBomRows(Transaction txn, List<ItemBomRow> rows) async {
    for (final row in rows) {
      final id = row.ibId;
      if (id == null) {
        continue;
      }
      await txn.update(
        'item_bom',
        row.toMap(),
        where: 'ib_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int> _deleteOrphanBomItemsInTransaction(
    Transaction txn, {
    required Set<int> validCatalogueIds,
  }) async {
    await _ensureBomIdsInTransaction(txn);
    final bomRows = await _fetchBomRows(txn);
    if (bomRows.isEmpty) {
      return 0;
    }

    final existingBomIds = bomRows.map((row) => row.ibId).whereType<int>().toSet();
    final orphanRootIds = bomRows
        .where((row) =>
            !validCatalogueIds.contains(row.ibItemId) ||
            (row.ibParentId != null && !existingBomIds.contains(row.ibParentId)))
        .map((row) => row.ibId)
        .whereType<int>()
        .toSet();

    if (orphanRootIds.isEmpty) {
      return 0;
    }

    final deletedBomIds = _collectBomSubtreeIds(bomRows, orphanRootIds);
    if (deletedBomIds.isNotEmpty) {
      await txn.delete(
        'item_bom',
        where: _whereInClause('ib_id', deletedBomIds.length),
        whereArgs: deletedBomIds,
      );
    }

    final remaining = await _fetchBomRows(txn);
    await _writeBomRows(txn, _renumberBomRows(_groupBomRowsByParent(remaining)));
    return deletedBomIds.length;
  }

  int _compareBomRows(ItemBomRow a, ItemBomRow b) {
    final orderCompare = a.ibOrder.compareTo(b.ibOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
  }

  List<int> _collectBomSubtreeIds(List<ItemBomRow> rows, Iterable<int> startIds) {
    final byParent = <int, List<ItemBomRow>>{};
    final byId = <int, ItemBomRow>{};

    for (final row in rows) {
      final id = row.ibId;
      if (id == null) {
        continue;
      }
      byId[id] = row;
      byParent.putIfAbsent(row.ibParentId ?? -1, () => []).add(row);
    }

    final visited = <int>{};
    final queue = <int>[...startIds];
    final result = <int>[];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) {
        continue;
      }
      result.add(current);
      final children = byParent[current] ?? const [];
      for (final child in children) {
        final childId = child.ibId;
        if (childId != null && byId.containsKey(childId)) {
          queue.add(childId);
        }
      }
    }

    return result;
  }

  String _whereInClause(String column, int count) {
    final placeholders = List<String>.filled(count, '?').join(', ');
    return '$column IN ($placeholders)';
  }

  String _bomLinkKey(int? parentId, int itemId) => '${parentId ?? 'null'}|$itemId';

  String _buildDuplicateCatalogueName({
    required String sourceName,
    required Set<String> existingNamesLower,
  }) {
    final baseName = sourceName.trim().isEmpty ? 'Artikel' : sourceName.trim();
    final copyBase = '$baseName (Kopie)';
    if (!existingNamesLower.contains(copyBase.toLowerCase())) {
      return copyBase;
    }

    var index = 2;
    while (true) {
      final candidate = '$copyBase $index';
      if (!existingNamesLower.contains(candidate.toLowerCase())) {
        return candidate;
      }
      index += 1;
    }
  }

  int _readInt(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _ensureBomIdsInTransaction(Transaction txn) async {
    final rows = await txn.query(
      'item_bom',
      columns: ['rowid', 'ib_id'],
      orderBy: 'rowid ASC',
    );

    var maxId = 0;
    final missingRowIds = <int>[];

    for (final row in rows) {
      final id = _readInt(row['ib_id']);
      if (id <= 0) {
        final rowId = _readInt(row['rowid']);
        if (rowId > 0) {
          missingRowIds.add(rowId);
        }
      } else if (id > maxId) {
        maxId = id;
      }
    }

    if (missingRowIds.isEmpty) {
      return;
    }

    var nextId = maxId + 1;
    for (final rowId in missingRowIds) {
      await txn.update(
        'item_bom',
        {'ib_id': nextId},
        where: 'rowid = ?',
        whereArgs: [rowId],
      );
      nextId += 1;
    }
  }
}