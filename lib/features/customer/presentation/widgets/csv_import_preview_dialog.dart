import 'package:flutter/material.dart';

import '../../domain/customer.dart';

class CsvImportPreviewDialog extends StatelessWidget {
  const CsvImportPreviewDialog({
    super.key,
    required this.customers,
    required this.onConfirm,
  });

  final List<Customer> customers;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CSV Import Vorschau'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${customers.length} gültige Kundendatensätze',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Zeige Vorschau der ersten 10 Datensätze:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DataTable(
                      headingRowColor: WidgetStateColor.resolveWith(
                        (states) => Colors.grey[200]!,
                      ),
                      columns: const [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('Nachname')),
                        DataColumn(label: Text('Vorname')),
                        DataColumn(label: Text('Stadt')),
                      ],
                      rows: customers.take(10).map((c) {
                        return DataRow(cells: [
                          DataCell(Text(c.cId, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(c.cLastName, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(c.cFirstName, style: const TextStyle(fontSize: 12))),
                          DataCell(Text(c.cCityB, style: const TextStyle(fontSize: 12))),
                        ]);
                      }).toList(),
                    ),
                    if (customers.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '... und ${customers.length - 10} weitere',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await Future.delayed(const Duration(milliseconds: 100));
            onConfirm();
          },
          child: const Text('Importieren'),
        ),
      ],
    );
  }
}
