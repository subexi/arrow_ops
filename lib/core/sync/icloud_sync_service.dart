import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ICloudSyncService {
  const ICloudSyncService();

  Future<File> resolveDatabaseFile() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'arrow_ops.db');
    return File(path);
  }

  Future<void> sync() async {
    // Platzhalter fur iCloud-Sync.
    // Fur eine echte iCloud-Synchronisierung wird ein nativer iCloud-Container
    // (NSUbiquitousContainers) und ein Platform-Channel benotigt.
    // Die Projektstruktur ist darauf vorbereitet und kann hier erweitert werden.
  }
}
