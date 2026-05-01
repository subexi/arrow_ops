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
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 60 : 16,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 680 : double.infinity,
          maxHeight: screenSize.height * 0.80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: const Text(
                'CSV Import Vorschau',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
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
                    ),
                    if (customers.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '... und ${customers.length - 10} weitere',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
