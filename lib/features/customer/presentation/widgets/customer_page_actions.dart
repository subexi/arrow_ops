import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomerPageActions extends StatelessWidget {
  const CustomerPageActions({
    super.key,
    required this.loading,
    required this.databasePath,
    required this.searchController,
    required this.onCreateCustomer,
    required this.onRefresh,
  });

  final bool loading;
  final String databasePath;
  final TextEditingController searchController;
  final VoidCallback onCreateCustomer;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Tooltip(
              message: 'Erstellt einen neuen Kundendatensatz.',
              child: CupertinoButton.filled(
                onPressed: loading ? null : onCreateCustomer,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.person_add, size: 18),
                    SizedBox(width: 8),
                    Text('Neuer Kunde'),
                  ],
                ),
              ),
            ),
            Tooltip(
              message: 'Lädt die Kundenliste neu aus der SQLite-Datenbank.',
              child: CupertinoButton(
                onPressed: loading ? null : onRefresh,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Aktualisieren'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          'SQLite: $databasePath',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        CupertinoSearchTextField(
          controller: searchController,
          placeholder: 'Kundendaten durchsuchen...',
        ),
      ],
    );
  }
}
