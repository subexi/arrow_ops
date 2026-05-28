import 'package:flutter/material.dart';

import '../../../core/ui/module_placeholder_page.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Auswertung',
      icon: Icons.query_stats_outlined,
      description:
          'Hier entstehen statistische Auswertungen mit Kennzahlen und Diagrammen.',
    );
  }
}
