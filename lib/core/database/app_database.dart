import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_path_config.dart';
import 'database_migration.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int _currentVersion = 2;

  Database? _database;

  final List<DatabaseMigration> _migrations = [
    DatabaseMigration(version: 1, run: _migrationV1),
    DatabaseMigration(version: 2, run: _migrationV2),
  ];

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final path = await _resolveDatabasePath();

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

  Future<String> _resolveDatabasePath() async {
    final preferredPath = DatabasePathConfig.databasePath;
    final migrationSources = <String>{
      await _defaultDatabasePath(),
      _legacyMacOsContainerDatabasePath(),
    };

    await _prepareDatabaseFile(
      preferredPath,
      migrationSourcePaths: migrationSources,
    );
    return preferredPath;
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
}
