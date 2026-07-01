import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../item/data/item_repository.dart';
import '../../item/domain/item_models.dart';
import '../data/parts_procurement_repository.dart';
import '../domain/parts_procurement_models.dart';
import 'widgets/parts_procurement_form_dialog.dart';

class PartsProcurementPage extends StatefulWidget {
  const PartsProcurementPage({super.key});

  @override
  State<PartsProcurementPage> createState() => _PartsProcurementPageState();
}

class _PartsProcurementPageState extends State<PartsProcurementPage> {
  final _repository = const PartsProcurementRepository();
  final _itemRepository = const ItemRepository();

  List<PartsProcurementRow> _rows = const [];
  List<ItemCatalogueRow> _catalogueItems = const [];
  bool _loading = true;
  String? _loadError;
  int? _selectedId;
  int? _sortColumnIndex = 1;
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    List<PartsProcurementRow> rows = const [];
    List<ItemCatalogueRow> catalogueItems = const [];
    String? errorMessage;

    try {
      rows = await _repository.getAll();
    } catch (error) {
      errorMessage = 'Bestandsdaten konnten nicht geladen werden: $error';
    }

    // Versuche Katalog zu laden, aber fail nicht wenn leer
    try {
      catalogueItems = await _itemRepository.getCatalogueItems();
    } catch (error) {
      final catalogueError = 'Artikelkatalog konnte nicht geladen werden: $error';
      errorMessage = errorMessage == null
          ? catalogueError
          : '$errorMessage\n$catalogueError';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _rows = rows;
      _catalogueItems = catalogueItems;
      _loadError = errorMessage;
      if (_selectedId == null || !_rows.any((row) => row.ppId == _selectedId)) {
        _selectedId = _rows.isEmpty ? null : _rows.first.ppId;
      }
      _loading = false;
    });

    // Zeige Error Dialog wenn wichtige Fehler auftraten
    if (errorMessage != null) {
      _showErrorDialog('Laden fehlgeschlagen', errorMessage);
    }
  }

  PartsProcurementRow? get _selectedRow {
    if (_selectedId == null) {
      return null;
    }
    for (final row in _rows) {
      if (row.ppId == _selectedId) {
        return row;
      }
    }
    return null;
  }

  Future<void> _createRow() async {
    final nextId = await _repository.nextId();
    if (!mounted) {
      return;
    }
    final created = await showDialog<PartsProcurementRow>(
      context: context,
      builder: (_) => PartsProcurementFormDialog(
        nextId: nextId,
        catalogueItems: _catalogueItems,
      ),
    );
    if (created == null) {
      return;
    }

    try {
      await _repository.save(created);
      await _loadData();
      if (!mounted) {
        return;
      }
      setState(() => _selectedId = created.ppId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag konnte nicht gespeichert werden')),
      );
      _showErrorDialog(
        'Speichern fehlgeschlagen',
        'Eintrag konnte nicht gespeichert werden:\n\n$error',
      );
    }
  }

  Future<void> _editSelectedRow() async {
    final selected = _selectedRow;
    if (selected == null) {
      return;
    }
    await _editRow(selected);
  }

  Future<void> _editRow(PartsProcurementRow selected) async {
    final edited = await showDialog<PartsProcurementRow>(
      context: context,
      builder: (_) => PartsProcurementFormDialog(
        nextId: selected.ppId,
        initialValue: selected,
        catalogueItems: _catalogueItems,
      ),
    );
    if (edited == null) {
      return;
    }

    try {
      await _repository.save(edited);
      await _loadData();
      if (!mounted) {
        return;
      }
      setState(() => _selectedId = edited.ppId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag konnte nicht gespeichert werden')),
      );
      _showErrorDialog(
        'Speichern fehlgeschlagen',
        'Eintrag konnte nicht gespeichert werden:\n\n$error',
      );
    }
  }

  Future<void> _deleteSelectedRow() async {
    final selected = _selectedRow;
    if (selected == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag löschen'),
        content: Text('Soll "${selected.ppIdi}" wirklich gelöscht werden?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      await _repository.deleteById(selected.ppId);
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag konnte nicht gelöscht werden')),
      );
      _showErrorDialog(
        'Löschen fehlgeschlagen',
        'Eintrag konnte nicht gelöscht werden:\n\n$error',
      );
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fehler in Zwischenablage kopiert')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Kopieren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _duplicateSelectedRow() async {
    final selected = _selectedRow;
    if (selected == null) {
      return;
    }

    try {
      final nextId = await _repository.nextId();
      final duplicated = selected.copyWith(ppId: nextId);
      await _repository.save(duplicated);
      await _loadData();
      if (!mounted) {
        return;
      }
      setState(() => _selectedId = duplicated.ppId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag dupliziert')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eintrag konnte nicht dupliziert werden')),
      );
      _showErrorDialog(
        'Duplizieren fehlgeschlagen',
        'Eintrag konnte nicht dupliziert werden:\n\n$error',
      );
    }
  }

  List<PartsProcurementRow> get _sortedRows {
    final rows = List<PartsProcurementRow>.from(_rows);
    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex == null) {
      return rows;
    }

    int compareString(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

    rows.sort((a, b) {
      late final int result;
      switch (sortColumnIndex) {
        case 0:
          result = compareString(a.ppIdi, b.ppIdi);
        case 1:
          result = compareString(a.ppPurchaseDate, b.ppPurchaseDate);
        case 2:
          result = a.ppQuantity.compareTo(b.ppQuantity);
        case 3:
          result = a.ppPriceNet.compareTo(b.ppPriceNet);
        case 4:
          result = a.ppTotalPriceNet.compareTo(b.ppTotalPriceNet);
        case 5:
          result = compareString(a.ppDescriptionDeLong, b.ppDescriptionDeLong);
        case 6:
          result = compareString(a.ppPointOfUse, b.ppPointOfUse);
        case 7:
          result = compareString(a.ppPartSource, b.ppPartSource);
        case 8:
          result = compareString(a.ppMaterial, b.ppMaterial);
        case 9:
          result = compareString(a.ppNote, b.ppNote);
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });

    return rows;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  DataColumn _column(String label, int index) => DataColumn(
    label: Text(label),
    onSort: _onSort,
  );

  DataCell _cell(PartsProcurementRow row, Widget child) => DataCell(
    child,
    onDoubleTap: () {
      setState(() => _selectedId = row.ppId);
      _editRow(row);
    },
  );

  DataCell _textCell(PartsProcurementRow row, String value, {double? width}) {
    final child = width == null
        ? Text(value.isEmpty ? '-' : value, overflow: TextOverflow.ellipsis)
        : SizedBox(
            width: width,
            child: Text(value.isEmpty ? '-' : value, overflow: TextOverflow.ellipsis),
          );
    return _cell(row, child);
  }

  DataCell _moneyCell(PartsProcurementRow row, double value) {
    final formatted = value.toStringAsFixed(2).replaceAll('.', ',');
    return _cell(row, Text(formatted));
  }

  Future<void> _exportToCsv() async {
    try {
      final fileName = 'bestandsfuehrung_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Bestandsführung als CSV exportieren',
        fileName: fileName,
        allowedExtensions: const ['csv'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.')),
          );
        }
        return;
      }

      final headers = [
        'Artikel-ID',
        'Kaufdatum',
        'Menge',
        'Preis netto',
        'Gesamtpreis netto',
        'Beschreibung',
        'Verwendung',
        'Lieferant',
        'Material',
        'Notiz',
      ];

      final csvLines = <String>[_escapeAndJoinCsv(headers)];
      for (final row in _sortedRows) {
        csvLines.add(_escapeAndJoinCsv([
          row.ppIdi,
          row.ppPurchaseDate,
          row.ppQuantity.toString(),
          row.ppPriceNet.toStringAsFixed(2),
          row.ppTotalPriceNet.toStringAsFixed(2),
          row.ppDescriptionDeLong,
          row.ppPointOfUse,
          row.ppPartSource,
          row.ppMaterial,
          row.ppNote,
        ]));
      }

      final csv = csvLines.join('\n');
      final csvWithBom = '\uFEFF$csv';
      await File(targetPath).writeAsString(csvWithBom, encoding: utf8);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV erfolgreich exportiert')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $error')),
        );
      }
    }
  }

  String _escapeAndJoinCsv(List<String> fields) {
    return fields
        .map((field) {
          final escaped = field.replaceAll('"', '""');
          return '"$escaped"';
        })
        .join(';');
  }

  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      final nextChar = i + 1 < line.length ? line[i + 1] : null;

      if (char == '"') {
        if (inQuotes && nextChar == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ';' && !inQuotes) {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }

    fields.add(current.toString());
    return fields;
  }

  Future<void> _importFromCsv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        dialogTitle: 'CSV-Datei zum Importieren wählen',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) return;

      final fileContent = await File(filePath).readAsString(encoding: utf8);
      final lines = fileContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV-Datei ist leer')),
          );
        }
        return;
      }

      int importedCount = 0;
      int errorCount = 0;

      for (int i = 1; i < lines.length; i++) {
        try {
          final fields = _parseCsvLine(lines[i]);
          if (fields.length < 10) continue;
          final hasLegacyDrawingColumn = fields.length >= 11;

          final nextId = await _repository.nextId();
          final newRow = PartsProcurementRow(
            ppId: nextId,
            ppIdi: fields[0].trim(),
            ppPurchaseDate: fields[1].trim(),
            ppQuantity: int.tryParse(fields[2].trim()) ?? 0,
            ppPriceNet: double.tryParse(fields[3].trim().replaceAll(',', '.')) ?? 0.0,
            ppTotalPriceNet: double.tryParse(fields[4].trim().replaceAll(',', '.')) ?? 0.0,
            ppDescriptionDeLong: fields[5].trim(),
            ppPointOfUse: fields[6].trim(),
            ppPartSource: fields[7].trim(),
            ppMaterial: fields[8].trim(),
            ppNote: (hasLegacyDrawingColumn ? fields[10] : fields[9]).trim(),
          );

          await _repository.save(newRow);
          importedCount++;
        } catch (error) {
          errorCount++;
        }
      }

      await _loadData();

      if (mounted) {
        final message = 'Import abgeschlossen: $importedCount importiert${errorCount > 0 ? ', $errorCount fehlgeschlagen' : ''}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $error')),
        );
      }
    }
  }

  Future<void> _exportToPdf() async {
    try {
      final fileName = 'bestandsfuehrung_${_buildFileTimestamp(DateTime.now())}.pdf';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Bestandsführung als PDF exportieren',
        fileName: fileName,
        allowedExtensions: const ['pdf'],
      );

      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.')),
          );
        }
        return;
      }

      final pdf = pw.Document();
      final rows = _sortedRows;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => [
            pw.Text(
              'Bestandsführung',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Erstellt: ${DateTime.now().toString().split('.')[0]}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [
                'Artikel-ID',
                'Kaufdatum',
                'Menge',
                'Preis netto',
                'Gesamtpreis',
                'Beschreibung',
                'Verwendung',
                'Lieferant',
                'Material',
                'Notiz',
              ],
              data: rows
                  .map((r) => [
                        r.ppIdi,
                        r.ppPurchaseDate,
                        r.ppQuantity.toString(),
                        '${r.ppPriceNet.toStringAsFixed(2).replaceAll('.', ',')} €',
                        '${r.ppTotalPriceNet.toStringAsFixed(2).replaceAll('.', ',')} €',
                        r.ppDescriptionDeLong,
                        r.ppPointOfUse,
                        r.ppPartSource,
                        r.ppMaterial,
                        r.ppNote,
                      ])
                  .toList(),
              cellHeight: 20,
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerHeight: 25,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(0.7),
                2: const pw.FlexColumnWidth(0.5),
                3: const pw.FlexColumnWidth(0.7),
                4: const pw.FlexColumnWidth(0.7),
                5: const pw.FlexColumnWidth(1.2),
                6: const pw.FlexColumnWidth(0.8),
                7: const pw.FlexColumnWidth(0.8),
                8: const pw.FlexColumnWidth(0.8),
                9: const pw.FlexColumnWidth(1.0),
              },
            ),
          ],
        ),
      );

      await pdf.save().then((data) async {
        await File(targetPath).writeAsBytes(data);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF erfolgreich exportiert')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF-Export fehlgeschlagen: $error')),
        );
      }
    }
  }

  Future<String?> _pickExportTargetPath({
    required String dialogTitle,
    required String fileName,
    required List<String> allowedExtensions,
  }) async {
    final result = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      allowedExtensions: allowedExtensions,
      type: FileType.custom,
    );
    return result;
  }

  String _buildFileTimestamp(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}_'
        '${dateTime.hour.toString().padLeft(2, '0')}-'
        '${dateTime.minute.toString().padLeft(2, '0')}-'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bestandsführung')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _createRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _selectedRow == null ? null : _editSelectedRow,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _selectedRow == null ? null : _deleteSelectedRow,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aktualisieren'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _selectedRow == null ? null : _duplicateSelectedRow,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Kopieren'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _exportToCsv,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('CSV Export'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _importFromCsv,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('CSV Import'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _exportToPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF Export'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Hinweis: Doppelklick auf eine Zeile startet den Bearbeiten-Modus.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _loadError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const Center(child: Text('Keine Einträge vorhanden.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          sortColumnIndex: _sortColumnIndex,
                          sortAscending: _sortAscending,
                          columns: [
                            _column('Bezeichnung', 0),
                            _column('Beschaffungsdatum', 1),
                            _column('Menge in Stk', 2),
                            _column('EK netto / Stk', 3),
                            _column('Gesamt EK netto', 4),
                            _column('Beschreibung', 5),
                            _column('Verwendung', 6),
                            _column('Lieferant', 7),
                            _column('Materialbeschreibung', 8),
                            _column('Notiz', 9),
                          ],
                          rows: _sortedRows
                              .map(
                                (row) => DataRow(
                                  selected: row.ppId == _selectedId,
                                  onSelectChanged: (_) => setState(() => _selectedId = row.ppId),
                                  cells: [
                                    _textCell(row, row.ppIdi),
                                    _textCell(row, row.ppPurchaseDate),
                                    _textCell(row, row.ppQuantity.toString()),
                                    _moneyCell(row, row.ppPriceNet),
                                    _moneyCell(row, row.ppTotalPriceNet),
                                    _textCell(row, row.ppDescriptionDeLong, width: 280),
                                    _textCell(row, row.ppPointOfUse),
                                    _textCell(row, row.ppPartSource),
                                    _textCell(row, row.ppMaterial),
                                    _textCell(row, row.ppNote),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
