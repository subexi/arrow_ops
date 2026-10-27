import 'dart:io';
import 'dart:convert';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
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
  final TextEditingController _searchController = TextEditingController();
  late final ScrollController _tableVerticalScrollController;
  late final ScrollController _tableHorizontalScrollController;

  List<PartsProcurementRow> _rows = const [];
  List<ItemCatalogueRow> _catalogueItems = const [];
  bool _loading = true;
  String? _loadError;
  int? _selectedId;
  Set<int> _selectedIds = <int>{};
  int? _sortColumnIndex = 1;
  bool _sortAscending = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tableVerticalScrollController = ScrollController();
    _tableHorizontalScrollController = ScrollController();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableVerticalScrollController.dispose();
    _tableHorizontalScrollController.dispose();
    super.dispose();
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
      final catalogueError =
          'Artikelkatalog konnte nicht geladen werden: $error';
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
      _selectedIds = _selectedIds
          .where((id) => _rows.any((row) => row.ppId == id))
          .toSet();
      if (_selectedId == null || !_rows.any((row) => row.ppId == _selectedId)) {
        _selectedId = _rows.isEmpty ? null : _rows.first.ppId;
      }
      if (_selectedId != null) {
        _selectedIds = {..._selectedIds, _selectedId!};
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
    final latestCatalogueItems = await _loadLatestCatalogueItems();
    if (!mounted) {
      return;
    }
    final created = await showDialog<PartsProcurementRow>(
      context: context,
      builder: (_) => PartsProcurementFormDialog(
        nextId: nextId,
        catalogueItems: latestCatalogueItems,
      ),
    );
    if (created == null) {
      return;
    }

    try {
      await _repository.save(created);
      _applySavedRow(created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eintrag konnte nicht gespeichert werden'),
        ),
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
      _applySavedRow(edited);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eintrag konnte nicht gespeichert werden'),
        ),
      );
      _showErrorDialog(
        'Speichern fehlgeschlagen',
        'Eintrag konnte nicht gespeichert werden:\n\n$error',
      );
    }
  }

  void _applySavedRow(PartsProcurementRow row) {
    if (!mounted) {
      return;
    }

    setState(() {
      final existingIndex = _rows.indexWhere(
        (existing) => existing.ppId == row.ppId,
      );
      if (existingIndex == -1) {
        _rows = [..._rows, row];
      } else {
        _rows = [..._rows]..[existingIndex] = row;
      }
      _selectedId = row.ppId;
      _selectedIds = {row.ppId};
    });
  }

  void _applyDeletedRow(int ppId) {
    if (!mounted) {
      return;
    }

    setState(() {
      final nextRows = _rows
          .where((row) => row.ppId != ppId)
          .toList(growable: false);
      _rows = nextRows;
      _selectedIds = _selectedIds.where((id) => id != ppId).toSet();
      if (_selectedId == ppId) {
        _selectedId = _selectedIds.isEmpty
            ? (nextRows.isEmpty ? null : nextRows.first.ppId)
            : _selectedIds.first;
      }
      if (_selectedId != null && !_selectedIds.contains(_selectedId)) {
        _selectedIds = {..._selectedIds, _selectedId!};
      }
    });
  }

  void _applyImportedRows(List<PartsProcurementRow> importedRows) {
    if (!mounted || importedRows.isEmpty) {
      return;
    }

    setState(() {
      final nextRows = [..._rows, ...importedRows];
      _rows = nextRows;
      _selectedId = importedRows.last.ppId;
      _selectedIds = {importedRows.last.ppId};
    });
  }

  Future<List<ItemCatalogueRow>> _loadLatestCatalogueItems() async {
    try {
      final latest = await _itemRepository.getCatalogueItems();
      if (mounted) {
        setState(() {
          _catalogueItems = latest;
        });
      }
      return latest;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Artikelkatalog konnte nicht aktualisiert werden: $error',
            ),
          ),
        );
      }
      return _catalogueItems;
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
      _applyDeletedRow(selected.ppId);
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
                  const SnackBar(
                    content: Text('Fehler in Zwischenablage kopiert'),
                  ),
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
      _applySavedRow(duplicated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Eintrag dupliziert')));
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

  bool _matchesSearch(PartsProcurementRow row, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final haystack = <String>[
      row.ppIdi,
      row.ppPurchaseDate,
      row.ppPaidDate,
      row.ppQuantity.toString(),
      row.ppPriceNet.toStringAsFixed(2),
      row.ppTotalPriceNet.toStringAsFixed(2),
      row.ppDescriptionDeLong,
      row.ppPointOfUse,
      row.ppPartSource,
      row.ppMaterial,
      row.ppNote,
    ].map((value) => value.trim().toLowerCase()).join(' ');

    return haystack.contains(normalizedQuery);
  }

  List<PartsProcurementRow> get _sortedRows {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final rows = _rows
        .where((row) => _matchesSearch(row, normalizedQuery))
        .toList(growable: false);
    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex == null) {
      return rows;
    }

    int compareString(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    rows.sort((a, b) {
      late final int result;
      switch (sortColumnIndex) {
        case 0:
          result = compareString(a.ppIdi, b.ppIdi);
        case 1:
          result = compareString(a.ppPurchaseDate, b.ppPurchaseDate);
        case 2:
          result = compareString(a.ppPaidDate, b.ppPaidDate);
        case 3:
          result = a.ppQuantity.compareTo(b.ppQuantity);
        case 4:
          result = a.ppPriceNet.compareTo(b.ppPriceNet);
        case 5:
          result = a.ppTotalPriceNet.compareTo(b.ppTotalPriceNet);
        case 6:
          result = compareString(a.ppDescriptionDeLong, b.ppDescriptionDeLong);
        case 7:
          result = compareString(a.ppPointOfUse, b.ppPointOfUse);
        case 8:
          result = compareString(a.ppPartSource, b.ppPartSource);
        case 9:
          result = compareString(a.ppMaterial, b.ppMaterial);
        case 10:
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

  DataColumn2 _column(String label, int index) =>
      DataColumn2(label: Text(label), onSort: _onSort);

  Future<void> _jumpToTableStart() {
    if (!_tableVerticalScrollController.hasClients) {
      return Future<void>.value();
    }

    return _tableVerticalScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _jumpToTableEnd() {
    if (!_tableVerticalScrollController.hasClients) {
      return Future<void>.value();
    }

    return _tableVerticalScrollController.animateTo(
      _tableVerticalScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  DataCell _cell(PartsProcurementRow row, Widget child) => DataCell(
    child,
    onDoubleTap: () {
      setState(() {
        _selectedId = row.ppId;
        _selectedIds = {row.ppId};
      });
      _editRow(row);
    },
  );

  Future<List<PartsProcurementRow>?> _resolveRowsForExport() async {
    final selectedRows = _sortedRows
        .where((row) => _selectedIds.contains(row.ppId))
        .toList(growable: false);

    if (selectedRows.isEmpty) {
      return _sortedRows;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export-Auswahl'),
        content: Text(
          '${selectedRows.length} Zeile(n) sind ausgewählt. Welche Daten sollen exportiert werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('all'),
            child: const Text('Alle Zeilen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('selected'),
            child: const Text('Ausgewählte Zeilen'),
          ),
        ],
      ),
    );

    if (choice == 'all') {
      return _sortedRows;
    }
    if (choice == 'selected') {
      return selectedRows;
    }
    return null;
  }

  DataCell _textCell(PartsProcurementRow row, String value, {double? width}) {
    final child = width == null
        ? Text(value.isEmpty ? '-' : value, overflow: TextOverflow.ellipsis)
        : SizedBox(
            width: width,
            child: Text(
              value.isEmpty ? '-' : value,
              overflow: TextOverflow.ellipsis,
            ),
          );
    return _cell(row, child);
  }

  DataCell _moneyCell(PartsProcurementRow row, double value) {
    final formatted = value.toStringAsFixed(2).replaceAll('.', ',');
    return _cell(row, Text(formatted));
  }

  Future<void> _exportToCsv() async {
    try {
      final rowsToExport = await _resolveRowsForExport();
      if (rowsToExport == null) {
        return;
      }
      final fileName =
          'bestandsfuehrung_${_buildFileTimestamp(DateTime.now())}.csv';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Bestandsführung als CSV exportieren',
        fileName: fileName,
        allowedExtensions: const ['csv'],
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Export abgebrochen: Kein Speicherort ausgewaehlt.',
              ),
            ),
          );
        }
        return;
      }

      final headers = [
        'Artikel-ID',
        'Kaufdatum',
        'Bezahlt',
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
      for (final row in rowsToExport) {
        csvLines.add(
          _escapeAndJoinCsv([
            row.ppIdi,
            row.ppPurchaseDate,
            row.ppPaidDate,
            row.ppQuantity.toString(),
            row.ppPriceNet.toStringAsFixed(2),
            row.ppTotalPriceNet.toStringAsFixed(2),
            row.ppDescriptionDeLong,
            row.ppPointOfUse,
            row.ppPartSource,
            row.ppMaterial,
            row.ppNote,
          ]),
        );
      }

      final csv = csvLines.join('\n');
      final csvWithBom = '\uFEFF$csv';
      await File(targetPath).writeAsString(csvWithBom, encoding: utf8);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'CSV erfolgreich exportiert (${rowsToExport.length} Zeile(n))',
            ),
          ),
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

  bool _hasCsvExtension(String path) {
    return path.trim().toLowerCase().endsWith('.csv');
  }

  Future<String?> _pickCsvPathWithFileSelector() async {
    if (!Platform.isMacOS) {
      return null;
    }

    XFile? xFile;
    try {
      xFile = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV-Datei', extensions: ['csv']),
        ],
        confirmButtonText: 'Auswaehlen',
      );
    } on MissingPluginException {
      return null;
    }

    final path = xFile?.path.trim();
    if (path == null || path.isEmpty || !_hasCsvExtension(path)) {
      return null;
    }
    return path;
  }

  Future<String?> _pickCsvPathWithFilePicker() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      dialogTitle: 'CSV-Datei zum Importieren wählen',
    );

    if (result.isEmpty) {
      return null;
    }

    final dynamic file = result.first;
    final directPath = file.path?.trim();
    if (directPath != null &&
        directPath.isNotEmpty &&
        _hasCsvExtension(directPath)) {
      return directPath;
    }

    List<int>? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    final name = file.name.trim();
    if (name.isEmpty || !_hasCsvExtension(name)) {
      return null;
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Die ausgewählte CSV-Datei konnte nicht gelesen werden (kein Dateiinhalte verfügbar).',
      );
    }

    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}arrow_ops_inventory_import_${DateTime.now().microsecondsSinceEpoch}.csv',
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  }

  Future<String?> _pickCsvImportPath() async {
    final selectorPath = await _pickCsvPathWithFileSelector();
    if (selectorPath != null) {
      return selectorPath;
    }
    return _pickCsvPathWithFilePicker();
  }

  Future<void> _importFromCsv() async {
    final importStopwatch = Stopwatch()..start();
    final stageDurationsMs = <String, int>{};
    var lastMarkMs = 0;

    void markStage(String stage) {
      final nowMs = importStopwatch.elapsedMilliseconds;
      stageDurationsMs[stage] = nowMs - lastMarkMs;
      lastMarkMs = nowMs;
    }

    String topStagesSummary() {
      if (stageDurationsMs.isEmpty) {
        return '-';
      }
      final sorted = stageDurationsMs.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top3 = sorted.take(3);
      return top3.map((entry) => '${entry.key}: ${entry.value} ms').join(', ');
    }

    try {
      final filePath = await _pickCsvImportPath();
      markStage('Datei auswählen');
      if (filePath == null || filePath.trim().isEmpty) {
        importStopwatch.stop();
        return;
      }

      final fileContent = await File(filePath).readAsString(encoding: utf8);
      markStage('Datei lesen');
      final lines = fileContent
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        importStopwatch.stop();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('CSV-Datei ist leer')));
        }
        return;
      }

      int importedCount = 0;
      int errorCount = 0;
      final headerFields = _parseCsvLine(
        lines.first,
      ).map((value) => value.trim().toLowerCase()).toList(growable: false);

      int? headerIndex(List<String> aliases) {
        for (final alias in aliases) {
          final index = headerFields.indexOf(alias);
          if (index >= 0) {
            return index;
          }
        }
        return null;
      }

      String fieldAt(List<String> fields, int? index) {
        if (index == null || index < 0 || index >= fields.length) {
          return '';
        }
        return fields[index].trim();
      }

      final articleIdIndex = headerIndex(['artikel-id']);
      final purchaseDateIndex = headerIndex(['kaufdatum', 'beschaffungsdatum']);
      final paidDateIndex = headerIndex(['bezahlt', 'bezahlt-datum']);
      final quantityIndex = headerIndex(['menge']);
      final priceNetIndex = headerIndex(['preis netto', 'ek netto / stk']);
      final totalPriceNetIndex = headerIndex([
        'gesamtpreis netto',
        'gesamt ek netto',
      ]);
      final descriptionIndex = headerIndex(['beschreibung']);
      final pointOfUseIndex = headerIndex(['verwendung']);
      final supplierIndex = headerIndex(['lieferant']);
      final materialIndex = headerIndex(['material', 'materialbeschreibung']);
      final noteIndex = headerIndex(['notiz']);
      var nextId = await _repository.nextId();
      final importedRows = <PartsProcurementRow>[];

      for (int i = 1; i < lines.length; i++) {
        try {
          final fields = _parseCsvLine(lines[i]);
          if (fields.length < 10) continue;
          final hasPaidDateColumnInRow = fields.length >= 11;

          String fallbackField(int legacyIndex, int shiftedIndex) {
            final targetIndex = hasPaidDateColumnInRow
                ? shiftedIndex
                : legacyIndex;
            if (targetIndex < 0 || targetIndex >= fields.length) {
              return '';
            }
            return fields[targetIndex].trim();
          }

          final fallbackPaidDate = hasPaidDateColumnInRow
              ? fallbackField(1, 2)
              : fallbackField(1, 1);

          final newRow = PartsProcurementRow(
            ppId: nextId,
            ppIdi: fieldAt(fields, articleIdIndex).isEmpty
                ? fields[0].trim()
                : fieldAt(fields, articleIdIndex),
            ppPurchaseDate: fieldAt(fields, purchaseDateIndex).isEmpty
                ? fields[1].trim()
                : fieldAt(fields, purchaseDateIndex),
            ppPaidDate: fieldAt(fields, paidDateIndex).isEmpty
                ? fallbackPaidDate
                : fieldAt(fields, paidDateIndex),
            ppQuantity:
                int.tryParse(
                  fieldAt(fields, quantityIndex).isEmpty
                      ? fallbackField(2, 3)
                      : fieldAt(fields, quantityIndex),
                ) ??
                0,
            ppPriceNet:
                double.tryParse(
                  (fieldAt(fields, priceNetIndex).isEmpty
                          ? fallbackField(3, 4)
                          : fieldAt(fields, priceNetIndex))
                      .replaceAll(',', '.'),
                ) ??
                0.0,
            ppTotalPriceNet:
                double.tryParse(
                  (fieldAt(fields, totalPriceNetIndex).isEmpty
                          ? fallbackField(4, 5)
                          : fieldAt(fields, totalPriceNetIndex))
                      .replaceAll(',', '.'),
                ) ??
                0.0,
            ppDescriptionDeLong: fieldAt(fields, descriptionIndex).isEmpty
                ? fallbackField(5, 6)
                : fieldAt(fields, descriptionIndex),
            ppPointOfUse: fieldAt(fields, pointOfUseIndex).isEmpty
                ? fallbackField(6, 7)
                : fieldAt(fields, pointOfUseIndex),
            ppPartSource: fieldAt(fields, supplierIndex).isEmpty
                ? fallbackField(7, 8)
                : fieldAt(fields, supplierIndex),
            ppMaterial: fieldAt(fields, materialIndex).isEmpty
                ? fallbackField(8, 9)
                : fieldAt(fields, materialIndex),
            ppNote: fieldAt(fields, noteIndex).isEmpty
                ? fallbackField(9, 10)
                : fieldAt(fields, noteIndex),
          );

          importedRows.add(newRow);
          nextId++;
          importedCount++;
        } catch (error) {
          errorCount++;
        }
      }
      markStage('CSV parsen & Datensätze aufbereiten');

      await _repository.insertAll(importedRows);
      markStage('DB schreiben');
      _applyImportedRows(importedRows);
      markStage('UI aktualisieren');
      importStopwatch.stop();
      final elapsedMs = importStopwatch.elapsedMilliseconds;
      debugPrint(
        '⏱️ Bestandsführung CSV-Import: $importedCount importiert'
        '${errorCount > 0 ? ', $errorCount fehlgeschlagen' : ''} '
        'in $elapsedMs ms | Top: ${topStagesSummary()}',
      );

      if (mounted) {
        final message =
            'Import abgeschlossen: $importedCount importiert'
            '${errorCount > 0 ? ', $errorCount fehlgeschlagen' : ''} '
            '($elapsedMs ms). Top: ${topStagesSummary()}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      importStopwatch.stop();
      final elapsedMs = importStopwatch.elapsedMilliseconds;
      debugPrint(
        '⏱️ Bestandsführung CSV-Import fehlgeschlagen nach $elapsedMs ms: '
        '$error | Top: ${topStagesSummary()}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import fehlgeschlagen nach $elapsedMs ms: $error '
              '(Top: ${topStagesSummary()})',
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportToPdf() async {
    try {
      final rowsToExport = await _resolveRowsForExport();
      if (rowsToExport == null) {
        return;
      }
      final fileName =
          'bestandsfuehrung_${_buildFileTimestamp(DateTime.now())}.pdf';
      final targetPath = await _pickExportTargetPath(
        dialogTitle: 'Bestandsführung als PDF exportieren',
        fileName: fileName,
        allowedExtensions: const ['pdf'],
      );

      if (targetPath == null || targetPath.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Export abgebrochen: Kein Speicherort ausgewaehlt.',
              ),
            ),
          );
        }
        return;
      }

      final pdf = pw.Document();
      final rows = rowsToExport;

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
                'Bezahlt',
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
                  .map(
                    (r) => [
                      r.ppIdi,
                      r.ppPurchaseDate,
                      r.ppPaidDate,
                      r.ppQuantity.toString(),
                      '${r.ppPriceNet.toStringAsFixed(2).replaceAll('.', ',')} €',
                      '${r.ppTotalPriceNet.toStringAsFixed(2).replaceAll('.', ',')} €',
                      r.ppDescriptionDeLong,
                      r.ppPointOfUse,
                      r.ppPartSource,
                      r.ppMaterial,
                      r.ppNote,
                    ],
                  )
                  .toList(),
              cellHeight: 20,
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerHeight: 25,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(0.7),
                2: const pw.FlexColumnWidth(0.7),
                3: const pw.FlexColumnWidth(0.5),
                4: const pw.FlexColumnWidth(0.7),
                5: const pw.FlexColumnWidth(0.7),
                6: const pw.FlexColumnWidth(1.2),
                7: const pw.FlexColumnWidth(0.8),
                8: const pw.FlexColumnWidth(0.8),
                9: const pw.FlexColumnWidth(0.8),
                10: const pw.FlexColumnWidth(1.0),
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
          SnackBar(
            content: Text(
              'PDF erfolgreich exportiert (${rows.length} Zeile(n))',
            ),
          ),
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
    if (Platform.isMacOS) {
      try {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            XTypeGroup(label: dialogTitle, extensions: allowedExtensions),
          ],
          confirmButtonText: 'Speichern',
        );
        final path = location?.path.trim();
        if (path != null && path.isNotEmpty) {
          return path;
        }
      } on MissingPluginException {
        // Fallback to file_picker when file_selector plugin is not registered.
      }
    }

    final selected = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: Uint8List(0),
      allowedExtensions: allowedExtensions,
      type: FileType.custom,
    );
    if (selected == null) {
      return null;
    }

    final dynamic value = selected;
    if (value is Uri) {
      return value.toFilePath();
    }
    return value.toString().trim().isEmpty ? null : value.toString().trim();
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
    final visibleRows = _sortedRows;
    final hasActiveSearch = _searchQuery.trim().isNotEmpty;
    final selectedRows = _rows
        .where((row) => _selectedIds.contains(row.ppId))
        .toList(growable: false);
    final selectedQuantitySum = selectedRows.fold<int>(
      0,
      (sum, row) => sum + row.ppQuantity,
    );
    final selectedTotalNetSum = selectedRows.fold<double>(
      0,
      (sum, row) => sum + row.ppTotalPriceNet,
    );
    final selectedTotalNetLabel = selectedTotalNetSum
        .toStringAsFixed(2)
        .replaceAll('.', ',');

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
                  onPressed: _loading || _selectedRow == null
                      ? null
                      : _editSelectedRow,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _selectedRow == null
                      ? null
                      : _deleteSelectedRow,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aktualisieren'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _rows.isEmpty
                      ? null
                      : _jumpToTableStart,
                  icon: const Icon(Icons.vertical_align_top),
                  label: const Text('Tabellenanfang'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _rows.isEmpty ? null : _jumpToTableEnd,
                  icon: const Icon(Icons.vertical_align_bottom),
                  label: const Text('Tabellenende'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading || _selectedRow == null
                      ? null
                      : _duplicateSelectedRow,
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
                  'Hinweis: Mehrfachauswahl per Checkbox möglich. Doppelklick auf eine Zeile startet den Bearbeiten-Modus.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                labelText: 'Bestandsdaten durchsuchen',
                hintText: 'Artikel, Datum, Lieferant, Material, Notiz ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasActiveSearch
                    ? IconButton(
                        tooltip: 'Suche löschen',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (selectedRows.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.summarize_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auswahl: ${selectedRows.length} Zeile(n) | Menge in Stk: $selectedQuantitySum | Gesamt EK netto: $selectedTotalNetLabel €',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedIds = <int>{};
                          _selectedId = null;
                        });
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Auswahl aufheben'),
                    ),
                  ],
                ),
              ),
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
                  : visibleRows.isEmpty
                  ? const Center(
                      child: Text('Keine Treffer für die aktuelle Suche.'),
                    )
                  : Scrollbar(
                      controller: _tableHorizontalScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: Scrollbar(
                        controller: _tableVerticalScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: DataTable2(
                          minWidth: 1450,
                          fixedTopRows: 1,
                          scrollController: _tableVerticalScrollController,
                          horizontalScrollController:
                              _tableHorizontalScrollController,
                          sortColumnIndex: _sortColumnIndex,
                          sortAscending: _sortAscending,
                          columns: [
                            _column('Bezeichnung', 0),
                            _column('Beschaffungsdatum', 1),
                            _column('Menge in Stk', 3),
                            _column('EK netto / Stk', 4),
                            _column('Gesamt EK netto', 5),
                            _column('Beschreibung', 6),
                            _column('Verwendung', 7),
                            _column('Lieferant', 8),
                            _column('Materialbeschreibung', 9),
                            _column('Notiz', 10),
                            _column('Bezahlt', 2),
                          ],
                          rows: visibleRows
                              .map(
                                (row) => DataRow(
                                  selected: _selectedIds.contains(row.ppId),
                                  onSelectChanged: (selected) {
                                    setState(() {
                                      if (selected == true) {
                                        _selectedIds = {
                                          ..._selectedIds,
                                          row.ppId,
                                        };
                                        _selectedId = row.ppId;
                                      } else {
                                        _selectedIds = _selectedIds
                                            .where((id) => id != row.ppId)
                                            .toSet();
                                        if (_selectedId == row.ppId) {
                                          _selectedId = _selectedIds.isEmpty
                                              ? null
                                              : _selectedIds.first;
                                        }
                                      }
                                    });
                                  },
                                  cells: [
                                    _textCell(row, row.ppIdi),
                                    _textCell(row, row.ppPurchaseDate),
                                    _textCell(row, row.ppQuantity.toString()),
                                    _moneyCell(row, row.ppPriceNet),
                                    _moneyCell(row, row.ppTotalPriceNet),
                                    _textCell(
                                      row,
                                      row.ppDescriptionDeLong,
                                      width: 280,
                                    ),
                                    _textCell(row, row.ppPointOfUse),
                                    _textCell(row, row.ppPartSource),
                                    _textCell(row, row.ppMaterial),
                                    _textCell(row, row.ppNote),
                                    _textCell(row, row.ppPaidDate),
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
