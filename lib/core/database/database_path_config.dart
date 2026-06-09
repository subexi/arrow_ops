import 'dart:io';

import 'package:path/path.dart' as p;

/// Zentral hinterlegter Speicherort fuer die SQLite-Datenbank.
class DatabasePathConfig {
  DatabasePathConfig._();

    static const String _macOsDatabaseDirectoryPath =
            '/Users/mba_hd/Development/Flutter/Projects/Data';

  static const String databaseFileName = 'arrow_ops.db';

    static String? get preferredDatabaseDirectoryPath {
        if (Platform.isMacOS) {
            return _macOsDatabaseDirectoryPath;
        }
        return null;
    }

    static String? get preferredDatabasePath {
        final dir = preferredDatabaseDirectoryPath;
        if (dir == null || dir.trim().isEmpty) {
            return null;
        }
        return p.join(dir, databaseFileName);
    }
}
