import 'package:flutter/cupertino.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final db = await AppDatabase.instance.database;
    debugPrint('🗄️ SQLite-Pfad: ${db.path}');
    final customerColumns = await db.rawQuery('PRAGMA table_info(customer)');
    final hasCLon = customerColumns.any((column) => column['name'] == 'c_lon');
    debugPrint('📋 customer-Spalten: ${customerColumns.length} Felder, c_lon vorhanden: $hasCLon');
  } catch (error) {
    debugPrint('⚠️ Datenbank konnte beim Start nicht initialisiert werden: $error');
  }

  runApp(const ArrowOpsApp());
}
