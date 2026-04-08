import 'package:flutter/material.dart';

import '../features/customer/presentation/customer_page.dart';

class ArrowOpsApp extends StatelessWidget {
  const ArrowOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arrow Ops',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005D77)),
        useMaterial3: true,
      ),
      home: const CustomerPage(),
    );
  }
}
