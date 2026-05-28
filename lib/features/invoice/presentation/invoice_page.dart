import 'package:flutter/material.dart';

import '../../../core/ui/module_placeholder_page.dart';

class InvoicePage extends StatelessWidget {
  const InvoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Rechnungen',
      icon: Icons.receipt_long_outlined,
      description:
          'Hier entsteht die Rechnungserstellung auf Grundlage fakturierter Aufträge.',
    );
  }
}
