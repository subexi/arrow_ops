import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import 'italian_billing_province_resolver.dart';
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

  Future<int> deleteAllCustomers() async {
    final db = await AppDatabase.instance.database;
    return db.delete('customer');
  }

  Future<List<CountryTld>> getAllCountries() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('country_tld', orderBy: 'co_tld ASC');
    return rows
        .map((r) => CountryTld(coTld: r['co_tld'] as String, coName: r['co_name'] as String))
        .toList();
  }

  Future<int> normalizeItalianAdministrativeUnits() async {
    final db = await AppDatabase.instance.database;

    final rows = await db.query(
      'customer',
      columns: [
        'c_id',
        'c_city_b',
        'c_postal_code_b',
        'c_state_b',
        'c_country_b_id',
        'c_city_d',
        'c_postal_code_d',
        'c_state_d',
        'c_country_d_id',
      ],
        where:
          'LOWER(TRIM(COALESCE(c_country_b_id,\'\'))) IN (\'it\', \'italy\', \'italien\', \'us\', \'usa\', \'united states\', \'united states of america\', \'vereinigte staaten\') '
          'OR LOWER(TRIM(COALESCE(c_country_d_id,\'\'))) IN (\'it\', \'italy\', \'italien\', \'us\', \'usa\', \'united states\', \'united states of america\', \'vereinigte staaten\')',
    );

    if (rows.isEmpty) {
      return 0;
    }

    final lookupCache = <String, String?>{};
    final updates = <Map<String, String>>[];

    for (final row in rows) {
      final id = row['c_id']?.toString();
      if (id == null || id.isEmpty) {
        continue;
      }

      final countryB = row['c_country_b_id']?.toString();
      final stateB = row['c_state_b']?.toString();
      final cityB = row['c_city_b']?.toString() ?? '';
      final postalB = row['c_postal_code_b']?.toString() ?? '';
      final resolvedB = await _resolveAdministrativeUnit(
        countryCode: countryB,
        currentState: stateB,
        city: cityB,
        postalCode: postalB,
        lookupCache: lookupCache,
      );

      final countryD = row['c_country_d_id']?.toString();
      final stateD = row['c_state_d']?.toString();
      final cityD = row['c_city_d']?.toString() ?? '';
      final postalD = row['c_postal_code_d']?.toString() ?? '';
      final resolvedD = await _resolveAdministrativeUnit(
        countryCode: countryD,
        currentState: stateD,
        city: cityD,
        postalCode: postalD,
        lookupCache: lookupCache,
      );

      final nextB = resolvedB.trim();
      final nextD = resolvedD.trim();
      final currentB = (stateB ?? '').trim();
      final currentD = (stateD ?? '').trim();
      final isItalyB = isItalyCountry(countryB);
      final isItalyD = isItalyCountry(countryD);
      final isUsB = isUsCountry(countryB);
      final isUsD = isUsCountry(countryD);

      final nextCityB = isItalyB
          ? appendItalianProvinceAbbreviationToCity(
              city: cityB,
              administrativeUnit: nextB,
            )
          : (isUsB
                ? appendUSStateAbbreviationToCity(
                    city: cityB,
                    administrativeUnit: nextB,
                  )
                : cityB);
      final nextCityD = isItalyD
          ? appendItalianProvinceAbbreviationToCity(
              city: cityD,
              administrativeUnit: nextD,
            )
          : (isUsD
                ? appendUSStateAbbreviationToCity(
                    city: cityD,
                    administrativeUnit: nextD,
                  )
                : cityD);
      final currentCityB = cityB.trim();
      final currentCityD = cityD.trim();

      if (currentB == nextB && currentD == nextD && currentCityB == nextCityB.trim() && currentCityD == nextCityD.trim()) {
        continue;
      }

      updates.add({
        'c_id': id,
        'c_state_b': nextB.isEmpty ? '-' : nextB,
        'c_state_d': nextD.isEmpty ? '-' : nextD,
        'c_city_b': nextCityB,
        'c_city_d': nextCityD,
      });
    }

    if (updates.isEmpty) {
      return 0;
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final update in updates) {
        batch.update(
          'customer',
          {
            'c_state_b': update['c_state_b']!,
            'c_state_d': update['c_state_d']!,
            'c_city_b': update['c_city_b']!,
            'c_city_d': update['c_city_d']!,
          },
          where: 'c_id = ?',
          whereArgs: [update['c_id']],
        );
      }
      await batch.commit(noResult: true);
    });

    return updates.length;
  }

  Future<String> _resolveAdministrativeUnit({
    required String? countryCode,
    required String? currentState,
    required String city,
    required String postalCode,
    required Map<String, String?> lookupCache,
  }) async {
    if (isItalyCountry(countryCode)) {
      var resolved = resolveItalianBillingProvince(
        countryCode: countryCode,
        currentState: currentState,
        city: city,
      );

      if (resolved != '-') {
        return resolved;
      }

      final cacheKey = 'it|${postalCode.trim().toLowerCase()}|${city.trim().toLowerCase()}';
      if (lookupCache.containsKey(cacheKey)) {
        return lookupCache[cacheKey] ?? resolved;
      }

      final fetched = await _resolveItalianFromNominatim(
        postalCode: postalCode,
        city: city,
      );
      lookupCache[cacheKey] = fetched;

      return fetched ?? resolved;
    }

    if (isUsCountry(countryCode)) {
      var resolved = resolveUSStateAdministrativeUnit(
        countryCode: countryCode,
        currentState: currentState,
        city: city,
      );

      if (resolved != '-') {
        return resolved;
      }

      final cacheKey = 'us|${postalCode.trim().toLowerCase()}|${city.trim().toLowerCase()}';
      if (lookupCache.containsKey(cacheKey)) {
        return lookupCache[cacheKey] ?? resolved;
      }

      final fetched = await _resolveUSFromNominatim(
        postalCode: postalCode,
        city: city,
      );
      lookupCache[cacheKey] = fetched;

      return fetched ?? resolved;
    }

    final fallbackState = currentState?.trim();
    return fallbackState == null || fallbackState.isEmpty ? '-' : fallbackState;
  }

  Future<String?> _resolveUSFromNominatim({
    required String postalCode,
    required String city,
  }) async {
    final normalizedPostal = postalCode.trim();
    final normalizedCity = city.trim();
    if (normalizedPostal.isEmpty && normalizedCity.isEmpty) {
      return null;
    }

    final params = <String, String>{
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
      'countrycodes': 'us',
    };
    if (normalizedPostal.isNotEmpty) {
      params['postalcode'] = normalizedPostal.split('-').first.trim();
    }
    if (normalizedCity.isNotEmpty) {
      params['city'] = normalizedCity;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'arrow_ops/1.0'},
      );
      if (response.statusCode != 200) {
        return null;
      }
      final parsed = jsonDecode(response.body);
      if (parsed is! List || parsed.isEmpty) {
        return null;
      }
      final first = parsed.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final address = first['address'];
      if (address is! Map<String, dynamic>) {
        return null;
      }

      final stateFull = address['state']?.toString().trim() ?? '';
      final isoRaw = address['ISO3166-2-lvl4']?.toString().trim() ?? '';
      final stateShort = isoRaw.contains('-') ? isoRaw.split('-').last.trim() : isoRaw;
      final mergedState =
          stateShort.isEmpty
              ? stateFull
              : (stateFull.isEmpty ? stateShort : '$stateShort - $stateFull');

      final resolved = resolveUSStateAdministrativeUnit(
        countryCode: 'us',
        currentState: mergedState,
        city: normalizedCity,
      );
      return resolved == '-' ? null : resolved;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveItalianFromNominatim({
    required String postalCode,
    required String city,
  }) async {
    final normalizedPostal = postalCode.trim();
    final normalizedCity = city.trim();
    if (normalizedPostal.isEmpty && normalizedCity.isEmpty) {
      return null;
    }

    final params = <String, String>{
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
      'countrycodes': 'it',
    };
    if (normalizedPostal.isNotEmpty) {
      params['postalcode'] = normalizedPostal;
    }
    if (normalizedCity.isNotEmpty) {
      params['city'] = normalizedCity;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'arrow_ops/1.0'},
      );
      if (response.statusCode != 200) {
        return null;
      }
      final parsed = jsonDecode(response.body);
      if (parsed is! List || parsed.isEmpty) {
        return null;
      }
      final first = parsed.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final address = first['address'];
      if (address is! Map<String, dynamic>) {
        return null;
      }

      final isoRaw =
          address['ISO3166-2-lvl6']?.toString().trim() ??
          address['ISO3166-2-lvl4']?.toString().trim() ??
          '';
      final isoShort = isoRaw.contains('-') ? isoRaw.split('-').last.trim() : isoRaw;
      final county = address['county']?.toString().trim() ?? '';

      var resolved = resolveItalianBillingProvince(
        countryCode: 'it',
        currentState: isoShort,
        city: normalizedCity.isEmpty ? county : normalizedCity,
      );

      if (resolved == '-') {
        resolved = resolveItalianBillingProvince(
          countryCode: 'it',
          currentState: county,
          city: normalizedCity,
        );
      }

      return resolved == '-' ? null : resolved;
    } catch (_) {
      return null;
    }
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
