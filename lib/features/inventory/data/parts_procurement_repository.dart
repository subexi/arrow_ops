import '../../../core/database/app_database.dart';
import '../domain/parts_procurement_models.dart';

class PartsProcurementRepository {
  const PartsProcurementRepository();

  Future<List<PartsProcurementRow>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'parts_procurement',
      orderBy: 'pp_purchase_date DESC, pp_id DESC',
    );
    return rows.map(PartsProcurementRow.fromMap).toList(growable: false);
  }

  Future<int> nextId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(pp_id), 0) + 1 AS next_id FROM parts_procurement',
    );
    return int.tryParse(rows.first['next_id']?.toString() ?? '') ?? 1;
  }

  Future<void> save(PartsProcurementRow row) async {
    final db = await AppDatabase.instance.database;
    
    // Validate pp_idi exists in item_catalogue (if not empty)
    if (row.ppIdi.isNotEmpty) {
      final itemCatalogueRows = await db.query(
        'item_catalogue',
        where: 'ic_idi = ? OR ic_ide = ? OR CAST(ic_id AS TEXT) = ?',
        whereArgs: [row.ppIdi, row.ppIdi, row.ppIdi],
        limit: 1,
      );
      if (itemCatalogueRows.isEmpty) {
        throw Exception('Artikel mit Bezeichnung "${row.ppIdi}" existiert nicht im Katalog');
      }
    }
    
    await db.transaction((txn) async {
      final updated = await txn.update(
        'parts_procurement',
        row.toMap(),
        where: 'pp_id = ?',
        whereArgs: [row.ppId],
      );
      if (updated == 0) {
        await txn.insert('parts_procurement', row.toMap());
      }
    });
  }

  Future<void> deleteById(int ppId) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      'parts_procurement',
      where: 'pp_id = ?',
      whereArgs: [ppId],
    );
  }
}
