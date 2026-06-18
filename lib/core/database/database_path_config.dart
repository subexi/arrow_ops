import 'dart:io';

import 'package:path/path.dart' as p;

/// Zentral hinterlegter Speicherort fuer die SQLite-Datenbank.
class DatabasePathConfig {
  DatabasePathConfig._();

    static const String _macOsDatabaseDirectoryPath =
            '/Users/mba_hd/Development/Flutter/Projects/Data';

    static String? _preferredDatabaseDirectoryPathOverride;

  static const String databaseFileName = 'arrow_ops.db';

    static String? get preferredDatabaseDirectoryPath {
        final override = _preferredDatabaseDirectoryPathOverride;
        if (override != null && override.trim().isNotEmpty) {
            return override;
        }
        if (Platform.isMacOS) {
            return _macOsDatabaseDirectoryPath;
        }
        return null;
    }

    static void setPreferredDatabaseDirectoryPathOverride(String? directoryPath) {
        final normalized = directoryPath?.trim();
        _preferredDatabaseDirectoryPathOverride =
                (normalized == null || normalized.isEmpty) ? null : normalized;
    }

    static String? get preferredDatabasePath {
        final dir = preferredDatabaseDirectoryPath;
        if (dir == null || dir.trim().isEmpty) {
            return null;
        }
        return p.join(dir, databaseFileName);
    }
}
