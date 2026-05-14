import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../domain/customer.dart';

class CsvImportPreviewDialog extends StatelessWidget {
  const CsvImportPreviewDialog({
    super.key,
    required this.customers,
    required this.onConfirm,
    this.replaceExisting = false,
  });

  final List<Customer> customers;
  final Future<void> Function() onConfirm;
  final bool replaceExisting;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 600;

    return CupertinoPopupSurface(
      isSurfacePainted: true,
      child: Dialog(
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
                    if (replaceExisting) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          border: Border.all(color: Colors.orange.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Achtung: Beim Import werden alle vorhandenen Kundendaten gelöscht.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
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
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: Navigator.of(context).pop,
                    child: const Text('Abbrechen'),
                  ),
                  CupertinoButton.filled(
                    onPressed: () async {
                      final navigator = Navigator.of(context);

                      if (replaceExisting) {
                        final confirmed = await showCupertinoDialog<bool>(
                          context: context,
                          builder: (dialogContext) => CupertinoAlertDialog(
                            title: const Text('Löschen wirklich durchführen?'),
                            content: const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Alle bestehenden Kundendatensätze werden vor dem Import gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.',
                              ),
                            ),
                            actions: [
                              CupertinoDialogAction(
                                onPressed: () => Navigator.of(dialogContext).pop(false),
                                child: const Text('Abbrechen'),
                              ),
                              CupertinoDialogAction(
                                isDestructiveAction: true,
                                onPressed: () => Navigator.of(dialogContext).pop(true),
                                child: const Text('Endgültig löschen'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed != true) {
                          return;
                        }
                      }

                      navigator.pop();
                      await Future.delayed(const Duration(milliseconds: 100));
                      await onConfirm();
                    },
                    child: Text(replaceExisting ? 'Löschen und importieren' : 'Importieren'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
