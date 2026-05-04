import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/country_tld.dart';
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
    await db.transaction((txn) async {
      await _ensureCountryExists(txn, customer.cCountryBId);
      await _ensureCountryExists(txn, customer.cCountryDId);

      await txn.insert(
        'customer',
        customer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<int> bulkUpsert(List<Customer> customers) async {
    if (customers.isEmpty) {
      return 0;
    }

    try {
      final db = await AppDatabase.instance.database;
      debugPrint('📊 Datenbank verbunden');

      return db.transaction((txn) async {
        debugPrint('🔄 Starte Batch-Insert mit ${customers.length} Einträgen');

        final countryCodes = _collectCountryCodes(customers);
        if (countryCodes.isNotEmpty) {
          debugPrint('🌍 Stelle ${countryCodes.length} Länderreferenzen sicher');
          for (final code in countryCodes) {
            await _ensureCountryExists(txn, code);
          }
        }
        
        final batch = txn.batch();
        
        for (int i = 0; i < customers.length; i++) {
          final customer = customers[i];
          try {
            final map = customer.toMap();
            batch.insert(
              'customer',
              map,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            debugPrint('❌ Fehler bei Customer $i (${customer.cId}): $e');
            rethrow;
          }
        }

        debugPrint('⏳ Führe Batch-Commit aus...');
        final result = await batch.commit();
        debugPrint('✅ Batch-Commit erfolgreich: ${result.length} Einträge');
        
        return result.length;
      });
    } catch (e, stackTrace) {
      debugPrint('🔥 bulkUpsert-Fehler: $e');
      debugPrint('📍 Stack: $stackTrace');
      rethrow;
    }
  }

  Future<int> bulkUpsertCountries(List<CountryTld> countries) async {
    if (countries.isEmpty) {
      return 0;
    }

    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final batch = txn.batch();

      for (final country in countries) {
        batch.insert(
          'country_tld',
          {
            'co_tld': country.coTld,
            'co_name': country.coName,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final result = await batch.commit();
      return result.length;
    });
  }

  Future<Customer?> getById(String customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'customer',
      where: 'c_id = ?',
      whereArgs: [customerId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return Customer.fromMap(rows.first);
  }

  Future<void> update(Customer customer) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await _ensureCountryExists(txn, customer.cCountryBId);
      await _ensureCountryExists(txn, customer.cCountryDId);

      await txn.update(
        'customer',
        customer.toMap(),
        where: 'c_id = ?',
        whereArgs: [customer.cId],
      );
    });
  }

  Future<void> delete(String customerId) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      'customer',
      where: 'c_id = ?',
      whereArgs: [customerId],
    );
  }

  Future<List<CountryTld>> getAllCountries() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('country_tld', orderBy: 'co_tld ASC');
    return rows
        .map((r) => CountryTld(coTld: r['co_tld'] as String, coName: r['co_name'] as String))
        .toList();
  }

  Future<int> deleteCountriesByCodes(List<String> rawCodes) async {
    final codes = rawCodes
        .map((code) => code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();

    if (codes.isEmpty) {
      return 0;
    }

    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      var deleted = 0;
      for (final code in codes) {
        deleted += await txn.delete(
          'country_tld',
          where: 'co_tld = ?',
          whereArgs: [code],
        );
      }
      return deleted;
    });
  }

  Set<String> _collectCountryCodes(List<Customer> customers) {
    final codes = <String>{};

    for (final customer in customers) {
      final billing = _normalizeCountryCode(customer.cCountryBId);
      final delivery = _normalizeCountryCode(customer.cCountryDId);

      if (billing != null) {
        codes.add(billing);
      }
      if (delivery != null) {
        codes.add(delivery);
      }
    }

    return codes;
  }

  String? _normalizeCountryCode(String? code) {
    final normalized = code?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == '-') {
      return null;
    }
    return normalized;
  }

  Future<void> _ensureCountryExists(DatabaseExecutor db, String? rawCode) async {
    final code = _normalizeCountryCode(rawCode);
    if (code == null) {
      return;
    }

    await db.insert(
      'country_tld',
      {
        'co_tld': code,
        'co_name': code.toUpperCase(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
