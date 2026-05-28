import 'package:flutter/material.dart';

import '../../../core/ui/module_placeholder_page.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Sync',
      icon: Icons.cloud_sync_outlined,
      description:
          'Hier entsteht die Übersicht für iCloud-Synchronisation, Status und Konflikte.',
    );
  }
}
