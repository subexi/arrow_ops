import '../../../core/database/app_database.dart';
import '../domain/incoming_invoice_row.dart';

class IncomingInvoiceOptions {
  const IncomingInvoiceOptions({
    required this.names,
    required this.usages,
    required this.kat1Values,
    required this.kat2Values,
    required this.countries,
  });

  final List<String> names;
  final List<String> usages;
  final List<String> kat1Values;
  final List<String> kat2Values;
  final List<String> countries;
}

class IncomingInvoiceRepository {
  const IncomingInvoiceRepository();

  Future<List<IncomingInvoiceRow>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'incoming_invoice',
      orderBy: 'ri_date DESC, ri_id DESC',
    );
    return rows.map(IncomingInvoiceRow.fromMap).toList(growable: false);
  }

  Future<int> nextId() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(ri_id), 0) + 1 AS next_id FROM incoming_invoice',
    );
    return int.tryParse(rows.first['next_id']?.toString() ?? '') ?? 1;
  }

  Future<void> save(IncomingInvoiceRow row) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'incoming_invoice',
        row.toMap(),
        where: 'ri_id = ?',
        whereArgs: [row.riId],
      );
      if (updated == 0) {
        await txn.insert('incoming_invoice', row.toMap());
      }
    });
  }

  Future<void> insertAll(List<IncomingInvoiceRow> rows) async {
    if (rows.isEmpty) {
      return;
    }
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert('incoming_invoice', row.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> deleteById(int riId) async {
    final db = await AppDatabase.instance.database;
    await db.delete('incoming_invoice', where: 'ri_id = ?', whereArgs: [riId]);
  }

  Future<IncomingInvoiceOptions> getOptions() async {
    final names = await _distinctValues('ri_name');
    final usages = await _distinctValues('ri_usage');
    final kat1Values = await _distinctValues('ri_kat1');
    final kat2Values = await _distinctValues('ri_kat2');
    final countries = await _distinctValues('ri_country');
    return IncomingInvoiceOptions(
      names: names,
      usages: usages,
      kat1Values: kat1Values,
      kat2Values: kat2Values,
      countries: countries,
    );
  }

  Future<List<String>> _distinctValues(String column) async {
    final database = await AppDatabase.instance.database;
    final result = await database.rawQuery('''
      SELECT DISTINCT TRIM(COALESCE($column, '')) AS value
      FROM incoming_invoice
      WHERE TRIM(COALESCE($column, '')) <> ''
      ORDER BY value COLLATE NOCASE ASC
    ''');
    return result
        .map((row) => row['value']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
