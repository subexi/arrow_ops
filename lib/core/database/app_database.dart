import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_path_config.dart';
import 'database_migration.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int _currentVersion = 22;

  Database? _database;
  String? _activeDatabasePath;

  String? get activeDatabasePath => _activeDatabasePath;

  final List<DatabaseMigration> _migrations = [
    DatabaseMigration(version: 1, run: _migrationV1),
    DatabaseMigration(version: 2, run: _migrationV2),
    DatabaseMigration(version: 3, run: _migrationV3),
    DatabaseMigration(version: 4, run: _migrationV4),
    DatabaseMigration(version: 5, run: _migrationV5),
    DatabaseMigration(version: 6, run: _migrationV6),
    DatabaseMigration(version: 7, run: _migrationV7),
    DatabaseMigration(version: 8, run: _migrationV8),
    DatabaseMigration(version: 9, run: _migrationV9),
    DatabaseMigration(version: 10, run: _migrationV10),
    DatabaseMigration(version: 11, run: _migrationV11),
    DatabaseMigration(version: 12, run: _migrationV12),
    DatabaseMigration(version: 13, run: _migrationV13),
    DatabaseMigration(version: 14, run: _migrationV14),
    DatabaseMigration(version: 15, run: _migrationV15),
    DatabaseMigration(version: 16, run: _migrationV16),
    DatabaseMigration(version: 17, run: _migrationV17),
    DatabaseMigration(version: 18, run: _migrationV18),
    DatabaseMigration(version: 19, run: _migrationV19),
    DatabaseMigration(version: 20, run: _migrationV20),
    DatabaseMigration(version: 21, run: _migrationV21),
    DatabaseMigration(version: 22, run: _migrationV22),
  ];

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final path = await _resolveDatabasePath();
    _activeDatabasePath = path;

    _database = await openDatabase(
      path,
      version: _currentVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        for (final migration in _migrations) {
          if (migration.version <= version) {
            await migration.run(db);
          }
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (final migration in _migrations) {
          if (migration.version > oldVersion && migration.version <= newVersion) {
            await migration.run(db);
          }
        }
      },
    );

    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
    _database = null;
    _activeDatabasePath = null;
  }

  Future<String> _resolveDatabasePath() async {
    final defaultPath = await _defaultDatabasePath();
    final preferredPath = DatabasePathConfig.preferredDatabasePath;
    final legacyPath = _legacyMacOsContainerDatabasePath();

    if (preferredPath == null) {
      await _prepareDatabaseFile(
        defaultPath,
        migrationSourcePaths: {legacyPath},
      );
      return defaultPath;
    }

    try {
      await _prepareDatabaseFile(
        preferredPath,
        migrationSourcePaths: {defaultPath, legacyPath},
      );
      return preferredPath;
    } on FileSystemException {
      await _prepareDatabaseFile(
        defaultPath,
        migrationSourcePaths: {preferredPath, legacyPath},
      );
      return defaultPath;
    }
  }

  Future<String> _defaultDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, DatabasePathConfig.databaseFileName);
  }

  String _legacyMacOsContainerDatabasePath() {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(
      home,
      'Library',
      'Containers',
      'com.example.arrowOps',
      'Data',
      'Documents',
      DatabasePathConfig.databaseFileName,
    );
  }

  Future<void> _prepareDatabaseFile(
    String targetPath, {
    Iterable<String> migrationSourcePaths = const [],
  }) async {
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    if (await targetFile.exists()) {
      return;
    }

    for (final sourcePath in migrationSourcePaths) {
      if (sourcePath == targetPath) {
        continue;
      }

      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        try {
          await sourceFile.rename(targetPath);
        } catch (_) {
          // Rename kann bei unterschiedlichen Volumes fehlschlagen.
          await sourceFile.copy(targetPath);
          await sourceFile.delete();
        }
        return;
      }
    }
  }

  static Future<void> _migrationV1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS country_tld (
        co_tld TEXT PRIMARY KEY NOT NULL,
        co_name TEXT DEFAULT '-' NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer (
        c_id TEXT PRIMARY KEY NOT NULL,
        c_company TEXT DEFAULT '-' NOT NULL,
        c_dealer INTEGER DEFAULT 0,
        c_vat INTEGER DEFAULT 0,
        c_vat_id TEXT DEFAULT '-' NOT NULL,
        c_last_name TEXT NOT NULL,
        c_first_name TEXT NOT NULL,
        c_careof_b TEXT DEFAULT '-' NOT NULL,
        c_street_b TEXT NOT NULL,
        c_house_number_b TEXT NOT NULL,
        c_postal_code_b TEXT NOT NULL,
        c_city_b TEXT NOT NULL,
        c_state_b TEXT DEFAULT '-' NOT NULL,
        c_country_b_id TEXT,
        c_careof_d TEXT DEFAULT '-' NOT NULL,
        c_street_d TEXT NOT NULL,
        c_house_number_d TEXT NOT NULL,
        c_postal_code_d TEXT NOT NULL,
        c_city_d TEXT NOT NULL,
        c_state_d TEXT DEFAULT '-' NOT NULL,
        c_country_d_id TEXT,
        c_mail TEXT DEFAULT '-' NOT NULL,
        c_phone TEXT DEFAULT '-' NOT NULL,
        c_web TEXT DEFAULT '-' NOT NULL,
        c_social_media TEXT DEFAULT '-' NOT NULL,
        c_lat REAL DEFAULT 0 NOT NULL,
        c_lon REAL DEFAULT 0 NOT NULL,
        c_note TEXT DEFAULT '-' NOT NULL,
        c_total_value_eur REAL DEFAULT 0 NOT NULL,
        c_total_value_usd REAL DEFAULT 0 NOT NULL,
        c_last_modified INTEGER DEFAULT 0 NOT NULL,
        FOREIGN KEY (c_country_b_id) REFERENCES country_tld(co_tld),
        FOREIGN KEY (c_country_d_id) REFERENCES country_tld(co_tld)
      )
    ''');
  }

  static Future<void> _migrationV2(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customer)');
    final hasCLong = columns.any((column) => column['name'] == 'c_long');
    final hasCLon = columns.any((column) => column['name'] == 'c_lon');

    if (hasCLong && !hasCLon) {
      await db.execute('ALTER TABLE customer RENAME COLUMN c_long TO c_lon');
    }
  }

  static Future<void> _migrationV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_catalogue (
        ic_id INTEGER NOT NULL,
        ic_idi TEXT,
        ic_ide TEXT,
        ic_idv TEXT,
        ic_description_de_long TEXT,
        ic_description_en_long TEXT,
        ic_color_code TEXT,
        ic_price_net REAL,
        ic_price_wholesale_net REAL,
        ic_purchase_price_net REAL,
        ic_weight REAL,
        ic_source_of_supply TEXT,
        ic_hts TEXT,
        ic_image_path TEXT,
        ic_note TEXT,
        ic_stock INTEGER,
        ic_ic INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_bom (
        ib_id INTEGER,
        ib_item_id INTEGER NOT NULL,
        ib_parent_id INTEGER,
        ib_order INTEGER DEFAULT 0 NOT NULL,
        ib_quantity INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _migrationV4(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(item_bom)');
    final hasIbOrder = columns.any((column) => column['name'] == 'ib_order');

    if (!hasIbOrder) {
      await db.execute('ALTER TABLE item_bom ADD COLUMN ib_order INTEGER DEFAULT 0 NOT NULL');
    }

    final rows = await db.query('item_bom', orderBy: 'COALESCE(ib_parent_id, -1) ASC, ib_id ASC');
    final byParent = <int?, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final parentId = row['ib_parent_id'] as int?;
      byParent.putIfAbsent(parentId, () => []).add(row);
    }

    for (final entry in byParent.entries) {
      final siblings = entry.value;
      for (var i = 0; i < siblings.length; i++) {
        final id = siblings[i]['ib_id'] as int?;
        if (id == null) {
          continue;
        }
        await db.update(
          'item_bom',
          {'ib_order': i + 1},
          where: 'ib_id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  static Future<void> _migrationV5(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(item_catalogue)');
    final hasColorColumn = columns.any((column) => column['name'] == 'ic_color_code');

    if (!hasColorColumn) {
      return;
    }

    await db.execute('''
      CREATE TABLE item_catalogue_v5 (
        ic_id INTEGER NOT NULL,
        ic_idi TEXT,
        ic_ide TEXT,
        ic_idv TEXT,
        ic_description_de_long TEXT,
        ic_description_en_long TEXT,
        ic_price_net REAL,
        ic_price_wholesale_net REAL,
        ic_purchase_price_net REAL,
        ic_weight REAL,
        ic_source_of_supply TEXT,
        ic_hts TEXT,
        ic_image_path TEXT,
        ic_note TEXT,
        ic_stock INTEGER,
        ic_ic INTEGER
      )
    ''');

    await db.execute('''
      INSERT INTO item_catalogue_v5 (
        ic_id,
        ic_idi,
        ic_ide,
        ic_idv,
        ic_description_de_long,
        ic_description_en_long,
        ic_price_net,
        ic_price_wholesale_net,
        ic_purchase_price_net,
        ic_weight,
        ic_source_of_supply,
        ic_hts,
        ic_image_path,
        ic_note,
        ic_stock,
        ic_ic
      )
      SELECT
        ic_id,
        ic_idi,
        ic_ide,
        ic_idv,
        ic_description_de_long,
        ic_description_en_long,
        ic_price_net,
        ic_price_wholesale_net,
        ic_purchase_price_net,
        ic_weight,
        ic_source_of_supply,
        ic_hts,
        ic_image_path,
        ic_note,
        ic_stock,
        ic_ic
      FROM item_catalogue
    ''');

    await db.execute('DROP TABLE item_catalogue');
    await db.execute('ALTER TABLE item_catalogue_v5 RENAME TO item_catalogue');
  }

  static Future<void> _migrationV6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS "order" (
        o_id TEXT NOT NULL PRIMARY KEY,
        o_customer_id TEXT NOT NULL,
        o_dealer INTEGER NOT NULL DEFAULT 0,
        o_date TEXT NOT NULL,
        o_currency TEXT NOT NULL DEFAULT 'EUR',
        o_language TEXT NOT NULL DEFAULT 'DE',
        o_price_basis TEXT NOT NULL DEFAULT 'net',
        o_vat_rate REAL NOT NULL,
        o_shipping REAL NOT NULL,
        o_value_goods REAL NOT NULL,
        o_total_price REAL NOT NULL,
        o_vat REAL NOT NULL,
        o_total_weight REAL NOT NULL,
        o_pay_date TEXT NOT NULL,
        o_payment INTEGER NOT NULL,
        o_paypal_fee REAL NOT NULL,
        o_delivery TEXT NOT NULL,
        o_tracking_code TEXT NOT NULL,
        o_note TEXT NOT NULL DEFAULT '-',
        FOREIGN KEY (o_customer_id) REFERENCES customer(c_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_ordered (
        io_id INTEGER NOT NULL PRIMARY KEY,
        io_order_id TEXT NOT NULL,
        io_pos INTEGER NOT NULL,
        io_quantity INTEGER NOT NULL,
        io_item_id INTEGER NOT NULL,
        io_idi TEXT NOT NULL,
        io_description_de_long TEXT NOT NULL,
        io_description_en_long TEXT NOT NULL,
        io_color TEXT NOT NULL DEFAULT '-',
        io_unit_price REAL NOT NULL DEFAULT 0,
        io_discount REAL NOT NULL DEFAULT 0,
        io_total_price REAL NOT NULL DEFAULT 0,
        io_item_weight REAL NOT NULL DEFAULT 0,
        io_total_weight REAL NOT NULL DEFAULT 0,
        io_photo TEXT NOT NULL DEFAULT '-',
        FOREIGN KEY (io_order_id) REFERENCES "order"(o_id),
        FOREIGN KEY (io_item_id) REFERENCES item_catalogue(ic_id)
      )
    ''');
  }

  static Future<void> _migrationV7(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(item_catalogue)');
    final hasPrimaryKey = columns.any(
      (column) => column['name'] == 'ic_id' && (column['pk'] as int? ?? 0) == 1,
    );

    if (hasPrimaryKey) {
      return;
    }

    await db.execute('''
      CREATE TABLE item_catalogue_v7 (
        ic_id INTEGER NOT NULL PRIMARY KEY,
        ic_idi TEXT,
        ic_ide TEXT,
        ic_idv TEXT,
        ic_description_de_long TEXT,
        ic_description_en_long TEXT,
        ic_price_net REAL,
        ic_price_wholesale_net REAL,
        ic_purchase_price_net REAL,
        ic_weight REAL,
        ic_source_of_supply TEXT,
        ic_hts TEXT,
        ic_image_path TEXT,
        ic_note TEXT,
        ic_stock INTEGER,
        ic_ic INTEGER
      )
    ''');

    await db.execute('''
      INSERT OR REPLACE INTO item_catalogue_v7 (
        ic_id,
        ic_idi,
        ic_ide,
        ic_idv,
        ic_description_de_long,
        ic_description_en_long,
        ic_price_net,
        ic_price_wholesale_net,
        ic_purchase_price_net,
        ic_weight,
        ic_source_of_supply,
        ic_hts,
        ic_image_path,
        ic_note,
        ic_stock,
        ic_ic
      )
      SELECT
        ic_id,
        ic_idi,
        ic_ide,
        ic_idv,
        ic_description_de_long,
        ic_description_en_long,
        ic_price_net,
        ic_price_wholesale_net,
        ic_purchase_price_net,
        ic_weight,
        ic_source_of_supply,
        ic_hts,
        ic_image_path,
        ic_note,
        ic_stock,
        ic_ic
      FROM item_catalogue
    ''');

    await db.execute('DROP TABLE item_catalogue');
    await db.execute('ALTER TABLE item_catalogue_v7 RENAME TO item_catalogue');
  }

  static Future<void> _migrationV8(Database db) async {
    final orderedColumns = await db.rawQuery('PRAGMA table_info(item_ordered)');
    if (orderedColumns.isEmpty) {
      // Falls item_ordered noch nicht existiert (z.B. bei inkonsistentem Altbestand), neu anlegen.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS item_ordered (
          io_id INTEGER NOT NULL PRIMARY KEY,
          io_order_id TEXT NOT NULL,
          io_pos INTEGER NOT NULL,
          io_quantity INTEGER NOT NULL,
          io_item_id INTEGER NOT NULL,
          io_idi TEXT NOT NULL,
          io_description_de_long TEXT NOT NULL,
          io_description_en_long TEXT NOT NULL,
          io_color TEXT NOT NULL DEFAULT '-',
          io_unit_price REAL NOT NULL DEFAULT 0,
          io_discount REAL NOT NULL DEFAULT 0,
          io_total_price REAL NOT NULL DEFAULT 0,
          io_item_weight REAL NOT NULL DEFAULT 0,
          io_total_weight REAL NOT NULL DEFAULT 0,
          io_photo TEXT NOT NULL DEFAULT '-',
          FOREIGN KEY (io_order_id) REFERENCES "order"(o_id),
          FOREIGN KEY (io_item_id) REFERENCES item_catalogue(ic_id)
        )
      ''');
      return;
    }

    // Rebuild der Tabelle stellt sicher, dass FK-Metadaten zur aktuellen item_catalogue-Struktur passen.
    await db.execute('''
      CREATE TABLE item_ordered_v8 (
        io_id INTEGER NOT NULL PRIMARY KEY,
        io_order_id TEXT NOT NULL,
        io_pos INTEGER NOT NULL,
        io_quantity INTEGER NOT NULL,
        io_item_id INTEGER NOT NULL,
        io_idi TEXT NOT NULL,
        io_description_de_long TEXT NOT NULL,
        io_description_en_long TEXT NOT NULL,
        io_color TEXT NOT NULL DEFAULT '-',
        io_unit_price REAL NOT NULL DEFAULT 0,
        io_discount REAL NOT NULL DEFAULT 0,
        io_total_price REAL NOT NULL DEFAULT 0,
        io_item_weight REAL NOT NULL DEFAULT 0,
        io_total_weight REAL NOT NULL DEFAULT 0,
        io_photo TEXT NOT NULL DEFAULT '-',
        FOREIGN KEY (io_order_id) REFERENCES "order"(o_id),
        FOREIGN KEY (io_item_id) REFERENCES item_catalogue(ic_id)
      )
    ''');

    await db.execute('''
      INSERT INTO item_ordered_v8 (
        io_id,
        io_order_id,
        io_pos,
        io_quantity,
        io_item_id,
        io_idi,
        io_description_de_long,
        io_description_en_long,
        io_color,
        io_unit_price,
        io_discount,
        io_total_price,
        io_item_weight,
        io_total_weight,
        io_photo
      )
      SELECT
        io_id,
        io_order_id,
        io_pos,
        io_quantity,
        io_item_id,
        io_idi,
        io_description_de_long,
        io_description_en_long,
        io_color,
        io_unit_price,
        io_discount,
        io_total_price,
        io_item_weight,
        io_total_weight,
        io_photo
      FROM item_ordered
    ''');

    await db.execute('DROP TABLE item_ordered');
    await db.execute('ALTER TABLE item_ordered_v8 RENAME TO item_ordered');
  }

  static Future<void> _migrationV9(Database db) async {
    final orderColumns = await db.rawQuery('PRAGMA table_info("order")');
    final hasLanguageColumn = orderColumns.any(
      (column) => column['name'] == 'o_language',
    );
    final hasPriceBasisColumn = orderColumns.any(
      (column) => column['name'] == 'o_price_basis',
    );

    if (!hasLanguageColumn) {
      await db.execute(
        "ALTER TABLE \"order\" ADD COLUMN o_language TEXT NOT NULL DEFAULT 'DE'",
      );
    }
    if (!hasPriceBasisColumn) {
      await db.execute(
        "ALTER TABLE \"order\" ADD COLUMN o_price_basis TEXT NOT NULL DEFAULT 'net'",
      );
    }
  }

  static Future<void> _migrationV10(Database db) async {
    final orderedColumns = await db.rawQuery('PRAGMA table_info(item_ordered)');
    final hasHtsColumn = orderedColumns.any(
      (column) => column['name'] == 'io_hts',
    );

    if (!hasHtsColumn) {
      await db.execute(
        "ALTER TABLE item_ordered ADD COLUMN io_hts TEXT NOT NULL DEFAULT '-'",
      );
    }
  }

  static Future<void> _migrationV11(Database db) async {
    final customerColumns = await db.rawQuery('PRAGMA table_info(customer)');
    final hasTotalValueEur = customerColumns.any(
      (column) => column['name'] == 'c_total_value_eur',
    );
    final hasTotalValueUsd = customerColumns.any(
      (column) => column['name'] == 'c_total_value_usd',
    );

    if (!hasTotalValueEur) {
      await db.execute(
        'ALTER TABLE customer ADD COLUMN c_total_value_eur REAL NOT NULL DEFAULT 0',
      );
    }
    if (!hasTotalValueUsd) {
      await db.execute(
        'ALTER TABLE customer ADD COLUMN c_total_value_usd REAL NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
      UPDATE customer
      SET c_total_value_eur = COALESCE((
        SELECT SUM(o.o_value_goods)
        FROM "order" o
        WHERE TRIM(COALESCE(o.o_customer_id, '')) = TRIM(COALESCE(customer.c_id, ''))
      ), 0)
    ''');
  }

  static Future<void> _migrationV12(Database db) async {
    final orderColumns = await db.rawQuery('PRAGMA table_info("order")');
    final hasTradeShowColumn = orderColumns.any(
      (column) => column['name'] == 'o_trade_show',
    );
    final hasPuttColumn = orderColumns.any(
      (column) => column['name'] == 'o_putt',
    );

    if (!hasTradeShowColumn) {
      await db.execute(
        "ALTER TABLE \"order\" ADD COLUMN o_trade_show TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!hasPuttColumn) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_putt INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<void> _migrationV13(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS parts_procurement (
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
  }

  static Future<void> _migrationV14(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(parts_procurement)');
    final hasDrawingColumn = columns.any(
      (column) => column['name'] == 'pp_drawing',
    );

    if (!hasDrawingColumn) {
      await db.execute(
        "ALTER TABLE parts_procurement ADD COLUMN pp_drawing TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<void> _migrationV15(Database db) async {
    // Ensure pp_drawing column exists (added in V14)
    final columns = await db.rawQuery('PRAGMA table_info(parts_procurement)');
    final hasDrawingColumn = columns.any(
      (column) => column['name'] == 'pp_drawing',
    );

    if (!hasDrawingColumn) {
      await db.execute(
        "ALTER TABLE parts_procurement ADD COLUMN pp_drawing TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<void> _migrationV16(Database db) async {
    // Remove Foreign Key constraint from parts_procurement table
    // FK to ic_idi doesn't work because ic_idi is not unique
    final columns = await db.rawQuery('PRAGMA table_info(parts_procurement)');
    if (columns.isEmpty) {
      return; // Table doesn't exist
    }

    // Temporarily disable FK checks to rebuild table
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      // Check if we need to rebuild (table might already be correct)
      final tableInfo = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='parts_procurement'",
      );
      final tableSql = tableInfo.isNotEmpty ? tableInfo.first['sql']?.toString() ?? '' : '';
      
      // If table still has FOREIGN KEY constraint, rebuild it without FK
      if (tableSql.contains('FOREIGN KEY')) {
        // Save existing data
        final existingRows = await db.query('parts_procurement');

        // Drop old table
        await db.execute('DROP TABLE parts_procurement');

        // Create new table without Foreign Key
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

        // Restore all data
        for (final row in existingRows) {
          await db.insert('parts_procurement', {
            'pp_id': row['pp_id'],
            'pp_idi': row['pp_idi'] ?? '',
            'pp_purchase_date': row['pp_purchase_date'] ?? '',
            'pp_quantity': row['pp_quantity'] ?? 0,
            'pp_price_net': row['pp_price_net'] ?? 0,
            'pp_total_price_net': row['pp_total_price_net'] ?? 0,
            'pp_description_de_long': row['pp_description_de_long'] ?? '',
            'pp_point_of_use': row['pp_point_of_use'] ?? '',
            'pp_part_source': row['pp_part_source'] ?? '',
            'pp_material': row['pp_material'] ?? '',
            'pp_note': row['pp_note'] ?? '',
            'pp_drawing': row['pp_drawing'] ?? '',
          });
        }
      }
    } finally {
      // Re-enable Foreign Keys
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  static Future<void> _migrationV17(Database db) async {
    final orderColumns = await db.rawQuery('PRAGMA table_info("order")');

    bool hasColumn(String name) =>
        orderColumns.any((column) => column['name'] == name);

    if (!hasColumn('o_delivery_address_different')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_address_different INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!hasColumn('o_delivery_name')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_name TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_street')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_street TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_house_number')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_house_number TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_postal_code')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_postal_code TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_city')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_city TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_state')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_state TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_country_id')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_country_id TEXT NOT NULL DEFAULT "-"',
      );
    }
    if (!hasColumn('o_delivery_lat')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_lat REAL NOT NULL DEFAULT 0',
      );
    }
    if (!hasColumn('o_delivery_lon')) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_delivery_lon REAL NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
      UPDATE "order"
      SET o_delivery_name = (
        SELECT TRIM(COALESCE(c_first_name, '') || ' ' || COALESCE(c_last_name, ''))
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_name, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_street = (
        SELECT COALESCE(c_street_b, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_street, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_house_number = (
        SELECT COALESCE(c_house_number_b, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_house_number, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_postal_code = (
        SELECT COALESCE(c_postal_code_b, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_postal_code, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_city = (
        SELECT COALESCE(c_city_b, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_city, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_state = (
        SELECT COALESCE(c_state_b, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_state, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_country_id = (
        SELECT COALESCE(c_country_b_id, '-')
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE TRIM(COALESCE(o_delivery_country_id, '')) IN ('', '-')
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_lat = (
        SELECT COALESCE(c_lat, 0)
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE COALESCE(o_delivery_lat, 0) = 0
    ''');

    await db.execute('''
      UPDATE "order"
      SET o_delivery_lon = (
        SELECT COALESCE(c_lon, 0)
        FROM customer
        WHERE customer.c_id = "order".o_customer_id
      )
      WHERE COALESCE(o_delivery_lon, 0) = 0
    ''');
  }

  static Future<void> _migrationV18(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_category (
        icat_id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    final itemCatalogueColumns = await db.rawQuery('PRAGMA table_info(item_catalogue)');
    final hasCategoryColumn = itemCatalogueColumns.any(
      (column) => column['name'] == 'category',
    );
    if (!hasCategoryColumn) {
      await db.execute(
        "ALTER TABLE item_catalogue ADD COLUMN category TEXT NOT NULL DEFAULT ''",
      );
    }

    final defaultCategories = <Map<String, Object>>[
      {'icat_id': 1, 'name': 'Nocks'},
      {'icat_id': 2, 'name': 'Schaefte'},
      {'icat_id': 3, 'name': 'Spitzen'},
      {'icat_id': 4, 'name': 'Werkzeuge'},
    ];
    for (final category in defaultCategories) {
      await db.insert(
        'item_category',
        category,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _migrationV19(Database db) async {
    final itemCatalogueColumns = await db.rawQuery('PRAGMA table_info(item_catalogue)');
    final hasArchiveColumn = itemCatalogueColumns.any(
      (column) => column['name'] == 'ic_archive',
    );
    if (!hasArchiveColumn) {
      await db.execute(
        'ALTER TABLE item_catalogue ADD COLUMN ic_archive INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<void> _migrationV20(Database db) async {
    final itemCatalogueColumns = await db.rawQuery('PRAGMA table_info(item_catalogue)');
    final hasDrawingColumn = itemCatalogueColumns.any(
      (column) => column['name'] == 'ic_drawing',
    );
    if (!hasDrawingColumn) {
      await db.execute(
        "ALTER TABLE item_catalogue ADD COLUMN ic_drawing TEXT NOT NULL DEFAULT ''",
      );
    }

    final partsColumns = await db.rawQuery('PRAGMA table_info(parts_procurement)');
    if (partsColumns.isEmpty) {
      return;
    }

    final hasPartsDrawingColumn = partsColumns.any(
      (column) => column['name'] == 'pp_drawing',
    );
    if (!hasPartsDrawingColumn) {
      return;
    }

    await db.execute('''
      CREATE TABLE parts_procurement_v20 (
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

    await db.execute('''
      INSERT INTO parts_procurement_v20 (
        pp_id,
        pp_idi,
        pp_purchase_date,
        pp_quantity,
        pp_price_net,
        pp_total_price_net,
        pp_description_de_long,
        pp_point_of_use,
        pp_part_source,
        pp_material,
        pp_note
      )
      SELECT
        pp_id,
        pp_idi,
        pp_purchase_date,
        pp_quantity,
        pp_price_net,
        pp_total_price_net,
        pp_description_de_long,
        pp_point_of_use,
        pp_part_source,
        pp_material,
        pp_note
      FROM parts_procurement
    ''');

    await db.execute('DROP TABLE parts_procurement');
    await db.execute('ALTER TABLE parts_procurement_v20 RENAME TO parts_procurement');
  }

  static Future<void> _migrationV21(Database db) async {
    final orderColumns = await db.rawQuery('PRAGMA table_info("order")');
    final hasFxToEurColumn = orderColumns.any(
      (column) => column['name'] == 'o_fx_to_eur',
    );

    if (!hasFxToEurColumn) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_fx_to_eur REAL NOT NULL DEFAULT 1',
      );
    }

    // Force USD orders without explicit rate to be fixed manually.
    await db.execute('''
      UPDATE "order"
      SET o_fx_to_eur = 0
      WHERE UPPER(TRIM(COALESCE(o_currency, 'EUR'))) = 'USD'
        AND COALESCE(o_fx_to_eur, 0) = 1
    ''');
  }

  static Future<void> _migrationV22(Database db) async {
    final orderColumns = await db.rawQuery('PRAGMA table_info("order")');
    final hasPaymentActualColumn = orderColumns.any(
      (column) => column['name'] == 'o_payment_actual',
    );
    final hasPaypalFeeActualColumn = orderColumns.any(
      (column) => column['name'] == 'o_paypal_fee_actual',
    );

    if (!hasPaymentActualColumn) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_payment_actual INTEGER',
      );
    }

    if (!hasPaypalFeeActualColumn) {
      await db.execute(
        'ALTER TABLE "order" ADD COLUMN o_paypal_fee_actual REAL',
      );
    }
  }
}
