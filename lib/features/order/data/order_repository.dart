import '../../../core/database/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../item/domain/item_models.dart';
import '../domain/order_models.dart';

class OrderRepository {
  const OrderRepository();

  static final ValueNotifier<int> orderDataVersion = ValueNotifier<int>(0);

  static void _notifyOrderDataChanged() {
    orderDataVersion.value = orderDataVersion.value + 1;
  }

  Future<List<OrderRow>> getOrders() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('"order"', orderBy: 'o_date DESC, o_id DESC');
    return rows.map(OrderRow.fromMap).toList();
  }

  Future<OrderRow?> getOrderById(String orderId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      '"order"',
      where: 'o_id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OrderRow.fromMap(rows.first);
  }

  Future<List<ItemOrderedRow>> getItemsForOrder(String orderId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        io.io_id,
        io.io_order_id,
        io.io_pos,
        io.io_quantity,
        io.io_item_id,
        io.io_idi,
        COALESCE(NULLIF(TRIM(ic.ic_ide), ''), '-') AS io_ide,
        io.io_description_de_long,
        io.io_description_en_long,
        COALESCE(NULLIF(TRIM(io.io_hts), '-'), NULLIF(TRIM(ic.ic_hts), ''), '-') AS io_hts,
        io.io_color,
        io.io_unit_price,
        io.io_discount,
        io.io_total_price,
        COALESCE(io.io_returned, 0) AS io_returned,
        COALESCE(NULLIF(TRIM(io.io_returned_date), ''), '-') AS io_returned_date,
        COALESCE(io.io_backorder_pending, 0) AS io_backorder_pending,
        COALESCE(NULLIF(TRIM(io.io_backorder_eta), ''), '-') AS io_backorder_eta,
        COALESCE(io.io_backorder_completed, 0) AS io_backorder_completed,
        COALESCE((
          SELECT SUM(COALESCE(component.ic_weight, 0) * COALESCE(child.ib_quantity, 0))
          FROM item_bom parent
          JOIN item_bom child ON child.ib_parent_id = parent.ib_id
          LEFT JOIN item_catalogue component ON component.ic_id = child.ib_item_id
          WHERE parent.ib_item_id = io.io_item_id
        ), NULLIF(io.io_item_weight, 0), COALESCE(ic.ic_weight, 0)) AS io_item_weight,
        (
          COALESCE((
            SELECT SUM(COALESCE(component.ic_weight, 0) * COALESCE(child.ib_quantity, 0))
            FROM item_bom parent
            JOIN item_bom child ON child.ib_parent_id = parent.ib_id
            LEFT JOIN item_catalogue component ON component.ic_id = child.ib_item_id
            WHERE parent.ib_item_id = io.io_item_id
          ), NULLIF(io.io_item_weight, 0), COALESCE(ic.ic_weight, 0))
          * COALESCE(io.io_quantity, 0)
        ) AS io_total_weight,
        COALESCE(NULLIF(TRIM(ic.ic_image_path), ''), NULLIF(TRIM(io.io_photo), '-'), '-') AS io_photo
      FROM item_ordered io
      LEFT JOIN item_catalogue ic ON ic.ic_id = io.io_item_id
      WHERE io.io_order_id = ?
      ORDER BY io.io_pos ASC
      ''',
      [orderId],
    );
    return rows.map(ItemOrderedRow.fromMap).toList();
  }

  Future<Map<String, int>> getItemCountsByOrderIds(Iterable<String> orderIds) async {
    final normalizedOrderIds = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedOrderIds.isEmpty) {
      return const {};
    }

    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(normalizedOrderIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT io_order_id, COUNT(*) AS item_count
      FROM item_ordered
      WHERE io_order_id IN ($placeholders)
      GROUP BY io_order_id
      ''',
      normalizedOrderIds,
    );

    final countsByOrderId = <String, int>{
      for (final orderId in normalizedOrderIds) orderId: 0,
    };

    for (final row in rows) {
      final orderId = row['io_order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty) {
        continue;
      }
      final count = int.tryParse(row['item_count']?.toString() ?? '') ?? 0;
      countsByOrderId[orderId] = count;
    }

    return countsByOrderId;
  }

  Future<Map<String, int>> getPendingBackorderCountsByOrderIds(
    Iterable<String> orderIds,
  ) async {
    final normalizedOrderIds = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedOrderIds.isEmpty) {
      return const {};
    }

    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(normalizedOrderIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT
        io_order_id,
        SUM(CASE WHEN COALESCE(io_backorder_pending, 0) != 0 THEN 1 ELSE 0 END)
          AS pending_backorder_count
      FROM item_ordered
      WHERE io_order_id IN ($placeholders)
      GROUP BY io_order_id
      ''',
      normalizedOrderIds,
    );

    final countsByOrderId = <String, int>{
      for (final orderId in normalizedOrderIds) orderId: 0,
    };

    for (final row in rows) {
      final orderId = row['io_order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty) {
        continue;
      }
      final count =
          int.tryParse(row['pending_backorder_count']?.toString() ?? '') ?? 0;
      countsByOrderId[orderId] = count;
    }

    return countsByOrderId;
  }

  Future<Map<String, int>> getReturnedItemCountsByOrderIds(
    Iterable<String> orderIds,
  ) async {
    final normalizedOrderIds = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedOrderIds.isEmpty) {
      return const {};
    }

    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(normalizedOrderIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT
        io_order_id,
        SUM(CASE WHEN COALESCE(io_returned, 0) != 0 THEN 1 ELSE 0 END)
          AS returned_item_count
      FROM item_ordered
      WHERE io_order_id IN ($placeholders)
      GROUP BY io_order_id
      ''',
      normalizedOrderIds,
    );

    final countsByOrderId = <String, int>{
      for (final orderId in normalizedOrderIds) orderId: 0,
    };

    for (final row in rows) {
      final orderId = row['io_order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty) {
        continue;
      }
      final count = int.tryParse(row['returned_item_count']?.toString() ?? '') ?? 0;
      countsByOrderId[orderId] = count;
    }

    return countsByOrderId;
  }

  Future<void> saveOrder(OrderRow order, {String? originalOrderId}) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final lookupId = (originalOrderId != null && originalOrderId.trim().isNotEmpty)
          ? originalOrderId.trim()
          : order.oId;

      String? previousCustomerId;
      int previousCanceled = 0;
      int previousReturned = 0;
      final existingRows = await txn.query(
        '"order"',
        columns: ['o_customer_id', 'o_canceled', 'o_returned'],
        where: 'o_id = ?',
        whereArgs: [lookupId],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = existingRows.first;
        previousCustomerId = existing['o_customer_id']?.toString();
        previousCanceled = int.tryParse(existing['o_canceled']?.toString() ?? '') ?? 0;
        previousReturned = int.tryParse(existing['o_returned']?.toString() ?? '') ?? 0;
      }

      final wasReturnedCancelled =
          previousCanceled != 0 && previousReturned != 0;
      final isReturnedCancelled =
          order.oCanceled != 0 && order.oReturned != 0;

      final updated = await txn.update(
        '"order"',
        order.toMap(),
        where: 'o_id = ?',
        whereArgs: [lookupId],
      );
      if (updated == 0) {
        await txn.insert('"order"', order.toMap());
      }

      if (!wasReturnedCancelled && isReturnedCancelled) {
        await _adjustStockForOrderItemsInTransaction(
          txn,
          orderId: order.oId,
          multiplier: 1,
        );
      } else if (wasReturnedCancelled && !isReturnedCancelled) {
        await _adjustStockForOrderItemsInTransaction(
          txn,
          orderId: order.oId,
          multiplier: -1,
        );
      }

      await _syncCustomerNetRevenueInTransaction(
        txn,
        <String>{
          order.oCustomerId,
          if (previousCustomerId != null && previousCustomerId.trim().isNotEmpty)
            previousCustomerId,
        },
      );
    });
    _notifyOrderDataChanged();
  }

  Future<void> syncItemDescriptionsFromCatalogueForOrder(String orderId) async {
    final db = await AppDatabase.instance.database;
    await db.rawUpdate(
      '''
      UPDATE item_ordered
      SET
        io_description_de_long = COALESCE(
          NULLIF((
            SELECT ic.ic_description_de_long
            FROM item_catalogue ic
            WHERE ic.ic_id = item_ordered.io_item_id
          ), ''),
          io_description_de_long
        ),
        io_description_en_long = COALESCE(
          NULLIF((
            SELECT ic.ic_description_en_long
            FROM item_catalogue ic
            WHERE ic.ic_id = item_ordered.io_item_id
          ), ''),
          io_description_en_long
        )
      WHERE io_order_id = ?
      ''',
      [orderId],
    );
  }

  Future<void> deleteOrder(String orderId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        '"order"',
        columns: ['o_customer_id', 'o_canceled', 'o_returned'],
        where: 'o_id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      final customerId = existingRows.isEmpty
          ? null
          : existingRows.first['o_customer_id']?.toString();
      final wasReturnedCancelled = existingRows.isNotEmpty &&
          (int.tryParse(existingRows.first['o_canceled']?.toString() ?? '') ?? 0) != 0 &&
          (int.tryParse(existingRows.first['o_returned']?.toString() ?? '') ?? 0) != 0;

      if (wasReturnedCancelled) {
        await _adjustStockForOrderItemsInTransaction(
          txn,
          orderId: orderId,
          multiplier: -1,
        );
      }

      await txn.delete(
        'item_ordered',
        where: 'io_order_id = ?',
        whereArgs: [orderId],
      );
      await txn.delete(
        '"order"',
        where: 'o_id = ?',
        whereArgs: [orderId],
      );

      await _syncCustomerNetRevenueInTransaction(
        txn,
        <String>{if (customerId != null && customerId.trim().isNotEmpty) customerId},
      );
    });
    _notifyOrderDataChanged();
  }

  Future<int> nextItemOrderedId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(io_id), 0) + 1 AS next_id FROM item_ordered',
    );
    return int.tryParse(rows.first['next_id']?.toString() ?? '') ?? 1;
  }

  Future<int> nextItemOrderedPos(String orderId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(io_pos), 0) + 1 AS next_pos FROM item_ordered WHERE io_order_id = ?',
      [orderId],
    );
    return int.tryParse(rows.first['next_pos']?.toString() ?? '') ?? 1;
  }

  Future<List<ItemCatalogueRow>> getSelectableCatalogueItems() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        ic.ic_id,
        ic.ic_idi,
        ic.ic_ide,
        ic.ic_idv,
        ic.ic_description_de_long,
        ic.ic_description_en_long,
        ic.ic_price_net,
        ic.ic_price_wholesale_net,
        ic.ic_purchase_price_net,
        COALESCE((
          SELECT SUM(COALESCE(component.ic_weight, 0) * COALESCE(child.ib_quantity, 0))
          FROM item_bom parent
          JOIN item_bom child ON child.ib_parent_id = parent.ib_id
          LEFT JOIN item_catalogue component ON component.ic_id = child.ib_item_id
          WHERE parent.ib_item_id = ic.ic_id
        ), ic.ic_weight) AS ic_weight,
        ic.ic_source_of_supply,
        ic.ic_hts,
        ic.ic_image_path,
        ic.ic_note,
        ic.ic_stock,
        ic.ic_ic
      FROM item_catalogue ic
      WHERE COALESCE(ic.ic_archive, 0) = 0
      ORDER BY ic.ic_idi COLLATE NOCASE ASC, ic.ic_id ASC
      ''',
    );
    return rows.map(ItemCatalogueRow.fromMap).toList(growable: false);
  }

  Future<void> saveItemOrdered(ItemOrderedRow item) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final orderRows = await txn.query(
        '"order"',
        columns: ['o_canceled', 'o_returned'],
        where: 'o_id = ?',
        whereArgs: [item.ioOrderId],
        limit: 1,
      );
      final stockReturnApplies = orderRows.isNotEmpty &&
          (int.tryParse(orderRows.first['o_canceled']?.toString() ?? '') ?? 0) != 0 &&
          (int.tryParse(orderRows.first['o_returned']?.toString() ?? '') ?? 0) != 0;

      final existing = item.ioId;
      final ioId = existing ?? await _nextItemOrderedIdInTransaction(txn);
      Map<String, Object?>? previousItemRow;
      if (existing != null) {
        final previousRows = await txn.query(
          'item_ordered',
          columns: ['io_item_id', 'io_quantity', 'io_returned'],
          where: 'io_id = ?',
          whereArgs: [existing],
          limit: 1,
        );
        if (previousRows.isNotEmpty) {
          previousItemRow = previousRows.first;
        }
      }

      final normalized = ItemOrderedRow(
        ioId: ioId,
        ioOrderId: item.ioOrderId,
        ioPos: item.ioPos,
        ioQuantity: item.ioQuantity,
        ioItemId: item.ioItemId,
        ioIdi: item.ioIdi,
        ioDescriptionDeLong: item.ioDescriptionDeLong,
        ioDescriptionEnLong: item.ioDescriptionEnLong,
        ioHts: item.ioHts,
        ioColor: item.ioColor,
        ioUnitPrice: item.ioUnitPrice,
        ioDiscount: item.ioDiscount,
        ioTotalPrice: item.ioTotalPrice,
        ioItemWeight: item.ioItemWeight,
        ioTotalWeight: item.ioTotalWeight,
        ioPhoto: item.ioPhoto,
        ioReturned: item.ioReturned,
        ioReturnedDate: item.ioReturnedDate,
        ioBackorderPending: item.ioBackorderPending,
        ioBackorderEta: item.ioBackorderEta,
        ioBackorderCompleted: item.ioBackorderCompleted,
      );

      final updated = await txn.update(
        'item_ordered',
        normalized.toMap(),
        where: 'io_id = ?',
        whereArgs: [ioId],
      );
      if (updated == 0) {
        await txn.insert('item_ordered', normalized.toMap());
      }

      final newItemId = normalized.ioItemId;
      final newReturnedQuantity = _effectiveReturnedQuantity(
        quantity: normalized.ioQuantity,
        itemReturnedFlag: normalized.ioReturned,
        orderReturnedCancelled: stockReturnApplies,
      );

      if (previousItemRow == null) {
        await _adjustItemStockInTransaction(
          txn,
          itemId: newItemId,
          quantityDelta: newReturnedQuantity,
        );
      } else {
        final oldItemId =
            int.tryParse(previousItemRow['io_item_id']?.toString() ?? '') ?? 0;
        final oldQuantity =
            int.tryParse(previousItemRow['io_quantity']?.toString() ?? '') ?? 0;
        final oldReturnedFlag =
            int.tryParse(previousItemRow['io_returned']?.toString() ?? '') ?? 0;
        final oldReturnedQuantity = _effectiveReturnedQuantity(
          quantity: oldQuantity,
          itemReturnedFlag: oldReturnedFlag,
          orderReturnedCancelled: stockReturnApplies,
        );

        if (oldItemId == newItemId) {
          final delta = newReturnedQuantity - oldReturnedQuantity;
          if (delta != 0) {
            await _adjustItemStockInTransaction(
              txn,
              itemId: newItemId,
              quantityDelta: delta,
            );
          }
        } else {
          if (oldItemId > 0 && oldReturnedQuantity != 0) {
            await _adjustItemStockInTransaction(
              txn,
              itemId: oldItemId,
              quantityDelta: -oldReturnedQuantity,
            );
          }
          if (newItemId > 0 && newReturnedQuantity != 0) {
            await _adjustItemStockInTransaction(
              txn,
              itemId: newItemId,
              quantityDelta: newReturnedQuantity,
            );
          }
        }
      }
    });
    _notifyOrderDataChanged();
  }

  Future<void> deleteItemOrdered(int ioId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'item_ordered',
        columns: ['io_order_id', 'io_item_id', 'io_quantity', 'io_returned'],
        where: 'io_id = ?',
        whereArgs: [ioId],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final row = rows.first;
        final orderId = row['io_order_id']?.toString().trim() ?? '';
        final itemId = int.tryParse(row['io_item_id']?.toString() ?? '') ?? 0;
        final quantity = int.tryParse(row['io_quantity']?.toString() ?? '') ?? 0;
        final itemReturnedFlag = int.tryParse(
              row['io_returned']?.toString() ?? '',
            ) ??
            0;

        if (orderId.isNotEmpty && itemId > 0 && quantity > 0) {
          final orderRows = await txn.query(
            '"order"',
            columns: ['o_canceled', 'o_returned'],
            where: 'o_id = ?',
            whereArgs: [orderId],
            limit: 1,
          );
          final stockReturnApplies = orderRows.isNotEmpty &&
              (int.tryParse(orderRows.first['o_canceled']?.toString() ?? '') ?? 0) != 0 &&
              (int.tryParse(orderRows.first['o_returned']?.toString() ?? '') ?? 0) != 0;

          final returnedQuantity = _effectiveReturnedQuantity(
            quantity: quantity,
            itemReturnedFlag: itemReturnedFlag,
            orderReturnedCancelled: stockReturnApplies,
          );

          if (returnedQuantity > 0) {
            await _adjustItemStockInTransaction(
              txn,
              itemId: itemId,
              quantityDelta: -returnedQuantity,
            );
          }
        }
      }

      await txn.delete(
        'item_ordered',
        where: 'io_id = ?',
        whereArgs: [ioId],
      );
    });
    _notifyOrderDataChanged();
  }

  Future<void> _adjustStockForOrderItemsInTransaction(
    Transaction txn, {
    required String orderId,
    required int multiplier,
  }) async {
    if (multiplier == 0) {
      return;
    }

    final rows = await txn.rawQuery(
      '''
      SELECT io_item_id, SUM(COALESCE(io_quantity, 0)) AS qty
      FROM item_ordered
      WHERE io_order_id = ?
        AND COALESCE(io_returned, 0) = 0
      GROUP BY io_item_id
      ''',
      [orderId],
    );

    for (final row in rows) {
      final itemId = int.tryParse(row['io_item_id']?.toString() ?? '') ?? 0;
      final quantity = int.tryParse(row['qty']?.toString() ?? '') ?? 0;
      if (itemId <= 0 || quantity == 0) {
        continue;
      }
      await _adjustItemStockInTransaction(
        txn,
        itemId: itemId,
        quantityDelta: quantity * multiplier,
      );
    }
  }

  Future<void> _adjustItemStockInTransaction(
    Transaction txn, {
    required int itemId,
    required int quantityDelta,
  }) async {
    if (itemId <= 0 || quantityDelta == 0) {
      return;
    }
    await txn.rawUpdate(
      '''
      UPDATE item_catalogue
      SET ic_stock = COALESCE(ic_stock, 0) + ?
      WHERE ic_id = ?
      ''',
      [quantityDelta, itemId],
    );
  }

  int _effectiveReturnedQuantity({
    required int quantity,
    required int itemReturnedFlag,
    required bool orderReturnedCancelled,
  }) {
    if (quantity <= 0) {
      return 0;
    }
    if (orderReturnedCancelled || itemReturnedFlag != 0) {
      return quantity;
    }
    return 0;
  }

  Future<int> _nextItemOrderedIdInTransaction(Transaction txn) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(io_id), 0) + 1 AS next_id FROM item_ordered',
    );
    return int.tryParse(rows.first['next_id']?.toString() ?? '') ?? 1;
  }

  Future<void> _syncCustomerNetRevenueInTransaction(
    Transaction txn,
    Set<String> customerIds,
  ) async {
    for (final customerId in customerIds) {
      final normalizedId = customerId.trim();
      if (normalizedId.isEmpty) {
        continue;
      }

      await txn.rawUpdate(
        '''
        UPDATE customer
        SET c_total_value_eur = COALESCE((
          SELECT SUM(
            CASE
              WHEN COALESCE(o_value_goods, 0) != 0
                   AND o_payment_actual IS NULL
                   AND o_paypal_fee_actual IS NULL
                   AND NOT (
                     COALESCE(o_canceled, 0) != 0
                     AND COALESCE(o_returned, 0) != 0
                   )
                THEN o_value_goods
              ELSE
                CASE
                  WHEN COALESCE(o_canceled, 0) != 0
                       AND COALESCE(o_returned, 0) != 0
                    THEN 0
                  ELSE
                    COALESCE(o_total_price, 0)
                    - COALESCE(o_shipping, 0)
                    - COALESCE(
                        CASE
                          WHEN o_paypal_fee_actual IS NOT NULL THEN o_paypal_fee_actual
                          WHEN o_payment_actual IS NOT NULL AND o_payment_actual != 1 THEN 0
                          ELSE o_paypal_fee
                        END,
                        0
                      )
                    - COALESCE(o_vat, 0)
                END
            END
          )
          FROM "order"
          WHERE TRIM(COALESCE(o_customer_id, '')) = ?
        ), 0)
        WHERE TRIM(COALESCE(c_id, '')) = ?
        ''',
        [normalizedId, normalizedId],
      );
    }
  }
}
