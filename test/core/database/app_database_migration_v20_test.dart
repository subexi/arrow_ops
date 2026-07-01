import 'dart:io';

import 'package:arrow_ops/core/database/app_database.dart';
import 'package:arrow_ops/core/database/database_path_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('arrow_ops_db_v20_migration_test_');
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    DatabasePathConfig.setPreferredDatabaseDirectoryPathOverride(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migriert v19 auf v20: entfernt pp_drawing und fuegt ic_drawing hinzu', () async {
    final legacyPath = p.join(tempDir.path, DatabasePathConfig.databaseFileName);

    final legacyDb = await openDatabase(
      legacyPath,
      version: 19,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE item_catalogue (
            ic_id INTEGER NOT NULL PRIMARY KEY,
            ic_idi TEXT,
            ic_archive INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE parts_procurement (
            pp_id INTEGER NOT NULL PRIMARY KEY,
            pp_idi TEXT NOT NULL DEFAULT '',
            pp_purchase_date TEXT NOT NULL DEFAULT '',
            pp_quantity INTEGER NOT NULL DEFAULT 0,
            pp_price_net REAL NOT NULL DEFAULT 0,
            pp_total_price_net REAL NOT NULL DEFAULT 0,
            pp_description_de_long TEXT NOT NULL DEFAULT '',
            pp_point_of_use TEXT NOT NULL DEFAULT '',
            pp_part_source TEXT NOT NULL DEFAULT '',
            pp_material TEXT NOT NULL DEFAULT '',
            pp_note TEXT NOT NULL DEFAULT '',
            pp_drawing TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
    );

    await legacyDb.insert('item_catalogue', {
      'ic_id': 1,
      'ic_idi': 'ART-1',
      'ic_archive': 0,
    });

    await legacyDb.insert('parts_procurement', {
      'pp_id': 1,
      'pp_idi': 'ART-1',
      'pp_purchase_date': '2026-06-29',
      'pp_quantity': 2,
      'pp_price_net': 5.5,
      'pp_total_price_net': 11.0,
      'pp_description_de_long': 'Test',
      'pp_point_of_use': 'Werkstatt',
      'pp_part_source': 'Lieferant A',
      'pp_material': 'Alu',
      'pp_note': 'Notiz',
      'pp_drawing': '/tmp/test.pdf',
    });

    await legacyDb.close();

    final migratedDb = await AppDatabase.instance.database;

    final itemColumns = await migratedDb.rawQuery('PRAGMA table_info(item_catalogue)');
    final partColumns = await migratedDb.rawQuery('PRAGMA table_info(parts_procurement)');

    final hasIcDrawing = itemColumns.any((column) => column['name'] == 'ic_drawing');
    final hasPpDrawing = partColumns.any((column) => column['name'] == 'pp_drawing');

    expect(hasIcDrawing, isTrue);
    expect(hasPpDrawing, isFalse);

    final itemRows = await migratedDb.query('item_catalogue', where: 'ic_id = ?', whereArgs: [1]);
    expect(itemRows, hasLength(1));
    expect(itemRows.single['ic_drawing'], '');

    final partRows = await migratedDb.query('parts_procurement', where: 'pp_id = ?', whereArgs: [1]);
    expect(partRows, hasLength(1));
    expect(partRows.single['pp_idi'], 'ART-1');
    expect(partRows.single['pp_note'], 'Notiz');
  });

  test('migriert v19 auf v20 idempotent wenn pp_drawing bereits fehlt', () async {
    final legacyPath = p.join(tempDir.path, DatabasePathConfig.databaseFileName);

    final legacyDb = await openDatabase(
      legacyPath,
      version: 19,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE item_catalogue (
            ic_id INTEGER NOT NULL PRIMARY KEY,
            ic_idi TEXT,
            ic_archive INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE parts_procurement (
            pp_id INTEGER NOT NULL PRIMARY KEY,
            pp_idi TEXT NOT NULL DEFAULT '',
            pp_purchase_date TEXT NOT NULL DEFAULT '',
            pp_quantity INTEGER NOT NULL DEFAULT 0,
            pp_price_net REAL NOT NULL DEFAULT 0,
            pp_total_price_net REAL NOT NULL DEFAULT 0,
            pp_description_de_long TEXT NOT NULL DEFAULT '',
            pp_point_of_use TEXT NOT NULL DEFAULT '',
            pp_part_source TEXT NOT NULL DEFAULT '',
            pp_material TEXT NOT NULL DEFAULT '',
            pp_note TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
    );

    await legacyDb.insert('item_catalogue', {
      'ic_id': 2,
      'ic_idi': 'ART-2',
      'ic_archive': 0,
    });

    await legacyDb.insert('parts_procurement', {
      'pp_id': 2,
      'pp_idi': 'ART-2',
      'pp_purchase_date': '2026-06-29',
      'pp_quantity': 3,
      'pp_price_net': 7.25,
      'pp_total_price_net': 21.75,
      'pp_description_de_long': 'Test ohne Zeichnung',
      'pp_point_of_use': 'Lager',
      'pp_part_source': 'Lieferant B',
      'pp_material': 'Stahl',
      'pp_note': 'Legacy ohne Spalte',
    });

    await legacyDb.close();

    final migratedDb = await AppDatabase.instance.database;

    final itemColumns = await migratedDb.rawQuery('PRAGMA table_info(item_catalogue)');
    final partColumns = await migratedDb.rawQuery('PRAGMA table_info(parts_procurement)');

    final hasIcDrawing = itemColumns.any((column) => column['name'] == 'ic_drawing');
    final hasPpDrawing = partColumns.any((column) => column['name'] == 'pp_drawing');

    expect(hasIcDrawing, isTrue);
    expect(hasPpDrawing, isFalse);

    final itemRows = await migratedDb.query('item_catalogue', where: 'ic_id = ?', whereArgs: [2]);
    expect(itemRows, hasLength(1));
    expect(itemRows.single['ic_drawing'], '');

    final partRows = await migratedDb.query('parts_procurement', where: 'pp_id = ?', whereArgs: [2]);
    expect(partRows, hasLength(1));
    expect(partRows.single['pp_idi'], 'ART-2');
    expect(partRows.single['pp_note'], 'Legacy ohne Spalte');
  });
}
