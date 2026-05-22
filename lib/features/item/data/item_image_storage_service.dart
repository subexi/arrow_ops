import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ItemImageStorageService {
  const ItemImageStorageService();

  static const String _imagesFolder = 'item_images';

  Future<String> normalizeForStorage({
    required String rawPath,
    required int itemId,
  }) async {
    final sourcePath = rawPath.trim();
    if (sourcePath.isEmpty) {
      return '';
    }

    final appDir = await getApplicationSupportDirectory();
    final appRoot = p.normalize(appDir.path);

    if (!p.isAbsolute(sourcePath)) {
      return p.normalize(sourcePath);
    }

    final normalizedSource = p.normalize(sourcePath);
    final isAlreadyManaged = p.isWithin(appRoot, normalizedSource);
    if (isAlreadyManaged) {
      return p.relative(normalizedSource, from: appRoot);
    }

    final sourceFile = File(normalizedSource);
    if (!await sourceFile.exists()) {
      return sourcePath;
    }

    final extension = p.extension(normalizedSource).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final filename = 'item_${itemId}_${DateTime.now().millisecondsSinceEpoch}$safeExtension';

    final managedDir = Directory(p.join(appRoot, _imagesFolder));
    if (!await managedDir.exists()) {
      await managedDir.create(recursive: true);
    }

    final destination = p.join(managedDir.path, filename);
    await sourceFile.copy(destination);

    return p.join(_imagesFolder, filename);
  }

  Future<String?> resolveAbsolutePath(String storedPath) async {
    final value = storedPath.trim();
    if (value.isEmpty) {
      return null;
    }

    if (p.isAbsolute(value)) {
      return value;
    }

    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, value);
  }
}
