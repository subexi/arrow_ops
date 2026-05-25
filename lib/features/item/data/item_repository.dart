import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/item_models.dart';

class ItemRepository {
  const ItemRepository();

  Future<List<ItemCatalogueRow>> getCatalogueItems() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('item_catalogue', orderBy: 'ic_id ASC');
    return rows.map(ItemCatalogueRow.fromMap).toList();
  }

  Future<int> deleteOrphanBomItems({required Set<int> validCatalogueIds}) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      return _deleteOrphanBomItemsInTransaction(
        txn,
        validCatalogueIds: validCatalogueIds,
      );
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
    });
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