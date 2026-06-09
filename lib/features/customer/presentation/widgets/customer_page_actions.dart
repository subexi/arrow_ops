import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomerPageActions extends StatelessWidget {
  const CustomerPageActions({
    super.key,
    required this.loading,
    required this.databasePath,
    this.databasePathFallbackActive = false,
    this.preferredDatabasePath,
    this.databaseStatusMessage,
    required this.searchController,
    required this.onCreateCustomer,
    required this.onRefresh,
  });

  final bool loading;
  final String databasePath;
  final bool databasePathFallbackActive;
  final String? preferredDatabasePath;
  final String? databaseStatusMessage;
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
        if (databasePathFallbackActive) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  preferredDatabasePath == null || preferredDatabasePath!.trim().isEmpty
                      ? 'Hinweis: Es wird ein Fallback-Datenbankpfad verwendet.'
                      : 'Hinweis: Der bevorzugte Datenbankpfad ist nicht verfügbar. Es wird ein Fallback-Pfad verwendet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
        if (databaseStatusMessage != null && databaseStatusMessage!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    databaseStatusMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        CupertinoSearchTextField(
          controller: searchController,
          placeholder: 'Kundendaten durchsuchen...',
        ),
      ],
    );
  }
}
