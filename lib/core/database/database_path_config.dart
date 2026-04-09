import 'package:path/path.dart' as p;

/// Zentral hinterlegter Speicherort fuer die SQLite-Datenbank.
class DatabasePathConfig {
  DatabasePathConfig._();

  static const String databaseDirectoryPath =
      '/Users/mba_hd/Development/Flutter/Projects/Data';

  static const String databaseFileName = 'arrow_ops.db';

  static String get databasePath =>
      p.join(databaseDirectoryPath, databaseFileName);
}
