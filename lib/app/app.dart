import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/customer/presentation/customer_page.dart';

class ArrowOpsApp extends StatelessWidget {
  const ArrowOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Arrow Ops',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: Color(0xFF005D77),
        barBackgroundColor: Color(0xFFF7F9FA),
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale('de'),
        Locale('en'),
      ],
      home: Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005D77)),
          useMaterial3: true,
        ),
        child: const ScaffoldMessenger(
          child: CustomerPage(),
        ),
      ),
    );
  }
}
