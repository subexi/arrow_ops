import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await AppDatabase.instance.database;
  } catch (error) {
    debugPrint('⚠️ Datenbank konnte beim Start nicht initialisiert werden: $error');
  }

  runApp(const ArrowOpsApp());
}
