import 'package:sqflite/sqflite.dart';

typedef MigrationRunner = Future<void> Function(Database db);

class DatabaseMigration {
  const DatabaseMigration({required this.version, required this.run});

  final int version;
  final MigrationRunner run;
}
