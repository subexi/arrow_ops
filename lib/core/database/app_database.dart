import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_path_config.dart';
import 'database_migration.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int _currentVersion = 1;

  Database? _database;

  final List<DatabaseMigration> _migrations = [
    DatabaseMigration(version: 1, run: _migrationV1),
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
    final defaultPath = await _defaultDatabasePath();

    try {
      await _prepareDatabaseFile(
        preferredPath,
        migrationSourcePath: defaultPath,
      );
      return preferredPath;
    } catch (_) {
      // Fallback fuer Plattformen/Umgebungen ohne Schreibzugriff auf den
      // konfigurierten absoluten Pfad.
      await _prepareDatabaseFile(defaultPath);
      return defaultPath;
    }
  }

  Future<String> _defaultDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, DatabasePathConfig.databaseFileName);
  }

  Future<void> _prepareDatabaseFile(
    String targetPath, {
    String? migrationSourcePath,
  }) async {
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    if (await targetFile.exists()) {
      return;
    }

    final sourcePath = migrationSourcePath;
    if (sourcePath == null || sourcePath == targetPath) {
      return;
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
        c_long REAL DEFAULT 0 NOT NULL,
        c_note TEXT DEFAULT '-' NOT NULL,
        c_total_value_eur REAL DEFAULT 0 NOT NULL,
        c_total_value_usd REAL DEFAULT 0 NOT NULL,
        c_last_modified INTEGER DEFAULT 0 NOT NULL,
        FOREIGN KEY (c_country_b_id) REFERENCES country_tld(co_tld),
        FOREIGN KEY (c_country_d_id) REFERENCES country_tld(co_tld)
      )
    ''');
  }
}
