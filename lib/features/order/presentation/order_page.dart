import 'package:flutter/material.dart';

import '../../../core/ui/module_placeholder_page.dart';

class OrderPage extends StatelessWidget {
  const OrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderPage(
      title: 'Aufträge',
      icon: Icons.assignment_outlined,
      description:
          'Hier entsteht die Auftragsbearbeitung mit Kunden-, Artikel- und Positionsdaten.',
    );
  }
}
