import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_shell.dart';
import 'app_theme.dart';

class ArrowOpsApp extends StatelessWidget {
  const ArrowOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arrow Ops',
      debugShowCheckedModeBanner: false,
      theme: ArrowOpsTheme.light(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('de'), Locale('en')],
      home: const ArrowOpsShell(),
    );
  }
}
