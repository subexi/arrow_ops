import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final db = await AppDatabase.instance.database;
    debugPrint('🗄️ SQLite-Pfad: ${db.path}');
  } catch (error) {
    debugPrint('⚠️ Datenbank konnte beim Start nicht initialisiert werden: $error');
  }

  runApp(const ArrowOpsApp());
}
