import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'icloud_sync_config.dart';

class ICloudSyncService {
  const ICloudSyncService();

  static const MethodChannel _channel = MethodChannel('arrow_ops/icloud');

  Future<File> resolveDatabaseFile() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'arrow_ops.db');
    return File(path);
  }

  Future<void> sync() async {
    // Fokus in dieser App: Dateisync fuer Artikelbilder.
    // Datensatz-Sync (CloudKit/Server) kann darauf aufbauen.
  }

  Future<String?> getICloudDocumentsPath({String? containerId}) async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return null;
    }

    final resolvedContainerId = _resolveContainerId(containerId);

    try {
      final path = await _channel.invokeMethod<String>(
        'getICloudDocumentsPath',
        <String, Object?>{'containerId': resolvedContainerId},
      );
      if (path == null || path.trim().isEmpty) {
        return null;
      }
      return path;
    } on MissingPluginException {
      if (kDebugMode) {
        debugPrint('ICloud channel nicht registriert.');
      }
      return null;
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('ICloud channel Fehler: ${error.code} ${error.message ?? ''}');
      }
      return null;
    }
  }

  Future<void> syncManagedImage(String relativePath, {String? containerId}) async {
    final normalizedRelativePath = p.normalize(relativePath.trim());
    if (normalizedRelativePath.isEmpty) {
      return;
    }

    final iCloudDocsPath = await getICloudDocumentsPath(containerId: containerId);
    if (iCloudDocsPath == null) {
      return;
    }

    final localRoot = (await getApplicationSupportDirectory()).path;
    final localImagePath = p.normalize(p.join(localRoot, normalizedRelativePath));
    final source = File(localImagePath);
    final iCloudImagePath = p.normalize(p.join(iCloudDocsPath, normalizedRelativePath));
    final destination = File(iCloudImagePath);

    final localExists = await source.exists();
    final iCloudExists = await destination.exists();

    if (!localExists && !iCloudExists) {
      return;
    }

    await source.parent.create(recursive: true);
    await destination.parent.create(recursive: true);

    if (localExists && !iCloudExists) {
      await source.copy(destination.path);
      return;
    }

    if (!localExists && iCloudExists) {
      await destination.copy(source.path);
      return;
    }

    final localStat = await source.stat();
    final iCloudStat = await destination.stat();
    if (localStat.modified.isAfter(iCloudStat.modified)) {
      await source.copy(destination.path);
    } else if (iCloudStat.modified.isAfter(localStat.modified)) {
      await destination.copy(source.path);
    }
  }

  String? _resolveContainerId(String? containerId) {
    final direct = containerId?.trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }

    final configured = ICloudSyncConfig.containerId.trim();
    if (configured.isEmpty) {
      return null;
    }
    return configured;
  }
}
