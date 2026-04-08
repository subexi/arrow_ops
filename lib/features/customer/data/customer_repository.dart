import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/customer.dart';

class CustomerRepository {
  const CustomerRepository();

  Future<List<Customer>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customer', orderBy: 'c_last_name ASC, c_first_name ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<void> upsert(Customer customer) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'customer',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> bulkUpsert(List<Customer> customers) async {
    if (customers.isEmpty) {
      return 0;
    }

    final db = await AppDatabase.instance.database;

    return db.transaction((txn) async {
      final batch = txn.batch();
      for (final customer in customers) {
        batch.insert(
          'customer',
          customer.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final result = await batch.commit(noResult: true);
      return result.length;
    });
  }
}
