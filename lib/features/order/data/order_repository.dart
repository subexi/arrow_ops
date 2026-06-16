import '../../../core/database/app_database.dart';
import 'package:sqflite/sqflite.dart';
import '../../item/domain/item_models.dart';
import '../domain/order_models.dart';

class OrderRepository {
  const OrderRepository();

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
        io.io_description_de_long,
        io.io_description_en_long,
        COALESCE(NULLIF(TRIM(io.io_hts), '-'), NULLIF(TRIM(ic.ic_hts), ''), '-') AS io_hts,
        io.io_color,
        io.io_unit_price,
        io.io_discount,
        io.io_total_price,
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

  Future<void> saveOrder(OrderRow order, {String? originalOrderId}) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final lookupId = (originalOrderId != null && originalOrderId.trim().isNotEmpty)
          ? originalOrderId.trim()
          : order.oId;
      final updated = await txn.update(
        '"order"',
        order.toMap(),
        where: 'o_id = ?',
        whereArgs: [lookupId],
      );
      if (updated == 0) {
        await txn.insert('"order"', order.toMap());
      }
    });
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
    });
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
      WHERE COALESCE(ic.ic_ic, 0) = 0
      ORDER BY ic.ic_idi COLLATE NOCASE ASC, ic.ic_id ASC
      ''',
    );
    return rows.map(ItemCatalogueRow.fromMap).toList(growable: false);
  }

  Future<void> saveItemOrdered(ItemOrderedRow item) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final existing = item.ioId;
      final ioId = existing ?? await _nextItemOrderedIdInTransaction(txn);
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
    });
  }

  Future<void> deleteItemOrdered(int ioId) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      'item_ordered',
      where: 'io_id = ?',
      whereArgs: [ioId],
    );
  }

  Future<int> _nextItemOrderedIdInTransaction(Transaction txn) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(io_id), 0) + 1 AS next_id FROM item_ordered',
    );
    return int.tryParse(rows.first['next_id']?.toString() ?? '') ?? 1;
  }
}
