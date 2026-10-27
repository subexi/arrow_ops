import 'dart:convert';
import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/incoming_invoice_repository.dart';
import '../domain/incoming_invoice_row.dart';
import 'widgets/incoming_invoice_form_dialog.dart';

class IncomingInvoicePage extends StatefulWidget {
  const IncomingInvoicePage({super.key});

  @override
  State<IncomingInvoicePage> createState() => _IncomingInvoicePageState();
}

class _IncomingInvoicePageState extends State<IncomingInvoicePage> {
  final _repository = const IncomingInvoiceRepository();
  final _searchController = TextEditingController();
  late final ScrollController _tableVerticalScrollController;
  late final ScrollController _tableHorizontalScrollController;

  List<IncomingInvoiceRow> _rows = const [];
  IncomingInvoiceOptions _options = const IncomingInvoiceOptions(
    names: [],
    usages: [],
    kat1Values: [],
    kat2Values: [],
    countries: [],
  );
  bool _loading = true;
  String? _loadError;
  String _searchQuery = '';
  String? _searchRegexError;
  int? _selectedId;
  int? _sortColumnIndex = 0;
  bool _sortAscending = false;

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
    try {
      final rows = await _repository.getAll();
      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _options = _buildOptionsFromRows(rows);
        if (_selectedId == null ||
            !_rows.any((row) => row.riId == _selectedId)) {
          _selectedId = _rows.isEmpty ? null : _rows.first.riId;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'Rechnungseingänge konnten nicht geladen werden: $error';
        _loading = false;
      });
    }
  }

  IncomingInvoiceRow? get _selectedRow {
    final id = _selectedId;
    if (id == null) {
      return null;
    }
    for (final row in _rows) {
      if (row.riId == id) {
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
    final created = await showDialog<IncomingInvoiceRow>(
      context: context,
      builder: (_) => IncomingInvoiceFormDialog(
        nextId: nextId,
        nameOptions: _options.names,
        usageOptions: _options.usages,
        kat1Options: _options.kat1Values,
        kat2Options: _options.kat2Values,
        countryOptions: _options.countries,
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
        SnackBar(
          content: Text('Eintrag konnte nicht gespeichert werden: $error'),
        ),
      );
    }
  }

  Future<void> _editSelectedRow() async {
    final selected = _selectedRow;
    if (selected == null) {
      return;
    }
    final edited = await showDialog<IncomingInvoiceRow>(
      context: context,
      builder: (_) => IncomingInvoiceFormDialog(
        nextId: selected.riId,
        initialValue: selected,
        nameOptions: _options.names,
        usageOptions: _options.usages,
        kat1Options: _options.kat1Values,
        kat2Options: _options.kat2Values,
        countryOptions: _options.countries,
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
        SnackBar(
          content: Text('Eintrag konnte nicht gespeichert werden: $error'),
        ),
      );
    }
  }

  void _applySavedRow(IncomingInvoiceRow row) {
    if (!mounted) {
      return;
    }
    setState(() {
      final existingIndex = _rows.indexWhere((item) => item.riId == row.riId);
      late final List<IncomingInvoiceRow> nextRows;
      if (existingIndex == -1) {
        nextRows = [..._rows, row];
      } else {
        nextRows = [..._rows]..[existingIndex] = row;
      }
      _rows = nextRows;
      _selectedId = row.riId;
      _options = _buildOptionsFromRows(nextRows);
    });
  }

  void _applyDeletedRow(int riId) {
    if (!mounted) {
      return;
    }
    setState(() {
      final nextRows = _rows
          .where((row) => row.riId != riId)
          .toList(growable: false);
      _rows = nextRows;
      if (_selectedId == riId) {
        _selectedId = nextRows.isEmpty ? null : nextRows.first.riId;
      }
      _options = _buildOptionsFromRows(nextRows);
    });
  }

  void _applyImportedRows(List<IncomingInvoiceRow> importedRows) {
    if (!mounted || importedRows.isEmpty) {
      return;
    }
    setState(() {
      final nextRows = [..._rows, ...importedRows];
      _rows = nextRows;
      _selectedId = importedRows.last.riId;
      _options = _buildOptionsFromRows(nextRows);
    });
  }

  IncomingInvoiceOptions _buildOptionsFromRows(List<IncomingInvoiceRow> rows) {
    List<String> distinct(Iterable<String> values) {
      final map = <String, String>{};
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        map.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
      }
      final sorted = map.values.toList(growable: false);
      sorted.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return sorted;
    }

    return IncomingInvoiceOptions(
      names: distinct(rows.map((row) => row.riName)),
      usages: distinct(rows.map((row) => row.riUsage)),
      kat1Values: distinct(rows.map((row) => row.riKat1)),
      kat2Values: distinct(rows.map((row) => row.riKat2)),
      countries: distinct(rows.map((row) => row.riCountry)),
    );
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    String? regexError;
    if (query.isNotEmpty) {
      try {
        RegExp(query, caseSensitive: false);
      } on FormatException catch (error) {
        regexError = error.message;
      }
    }
    setState(() {
      _searchQuery = value;
      _searchRegexError = regexError;
    });
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
        content: Text('Soll der Eintrag "${selected.riName}" gelöscht werden?'),
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
      await _repository.deleteById(selected.riId);
      _applyDeletedRow(selected.riId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eintrag konnte nicht gelöscht werden: $error')),
      );
    }
  }

  List<IncomingInvoiceRow> get _visibleRows {
    final query = _searchQuery.trim();
    if (query.isNotEmpty && _searchRegexError != null) {
      return const [];
    }
    final matcher = query.isEmpty ? null : RegExp(query, caseSensitive: false);

    final filtered = _rows
        .where((row) {
          if (matcher == null) {
            return true;
          }
          final haystack = [
            row.riDate,
            row.riName,
            row.riUsage,
            row.riKat1,
            row.riKat2,
            row.riCountry,
            row.riGross.toStringAsFixed(2),
            row.riVatRate.toStringAsFixed(2),
            row.riNet.toStringAsFixed(2),
            row.riVat.toStringAsFixed(2),
          ].join(' ');
          return matcher.hasMatch(haystack);
        })
        .toList(growable: false);

    final sortColumnIndex = _sortColumnIndex;
    if (sortColumnIndex == null) {
      return filtered;
    }

    int compareString(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());

    filtered.sort((a, b) {
      late final int result;
      switch (sortColumnIndex) {
        case 0:
          result = compareString(a.riDate, b.riDate);
        case 1:
          result = compareString(a.riName, b.riName);
        case 2:
          result = compareString(a.riUsage, b.riUsage);
        case 3:
          result = compareString(a.riKat1, b.riKat1);
        case 4:
          result = compareString(a.riKat2, b.riKat2);
        case 5:
          result = compareString(a.riCountry, b.riCountry);
        case 6:
          result = a.riGross.compareTo(b.riGross);
        case 7:
          result = a.riVatRate.compareTo(b.riVatRate);
        case 8:
          result = a.riNet.compareTo(b.riNet);
        case 9:
          result = a.riVat.compareTo(b.riVat);
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
    return filtered;
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  Future<String?> _pickImportPath() async {
    if (Platform.isMacOS) {
      try {
        final selected = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'CSV-Datei', extensions: ['csv']),
          ],
          confirmButtonText: 'Auswählen',
        );
        final selectedPath = selected?.path.trim();
        if (selectedPath != null && selectedPath.isNotEmpty) {
          return selectedPath;
        }
      } on MissingPluginException {
        // Fallback to file_picker.
      }
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      dialogTitle: 'CSV-Datei importieren',
    );
    if (result.isEmpty) {
      return null;
    }
    final file = result.first;
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      return path;
    }
    final bytes = await file.readAsBytes();
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}arrow_ops_incoming_invoice_import_${DateTime.now().microsecondsSinceEpoch}.csv',
    );
    await tempFile.writeAsBytes(bytes, flush: true);
    return tempFile.path;
  }

  Future<String?> _pickExportPath({required String fileName}) async {
    if (Platform.isMacOS) {
      try {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'CSV-Datei', extensions: ['csv']),
          ],
          confirmButtonText: 'Speichern',
        );
        final selectedPath = location?.path.trim();
        if (selectedPath != null && selectedPath.isNotEmpty) {
          return selectedPath;
        }
      } on MissingPluginException {
        // Fallback to file_picker.
      }
    }

    final selected = await FilePicker.saveFile(
      dialogTitle: 'CSV exportieren',
      fileName: fileName,
      bytes: Uint8List(0),
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (selected == null) {
      return null;
    }
    final dynamic value = selected;
    if (value is Uri) {
      return value.toFilePath();
    }
    final asString = value.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  String _timestamp(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$year$month${day}_$hour$minute$second';
  }

  String _sanitizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
  }

  double _parseAmount(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return 0;
    }
    final lastComma = raw.lastIndexOf(',');
    final lastDot = raw.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
        return double.tryParse(normalized) ?? 0;
      }
      final normalized = raw.replaceAll(',', '');
      return double.tryParse(normalized) ?? 0;
    }
    if (lastComma >= 0) {
      return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    }
    return double.tryParse(raw) ?? 0;
  }

  List<String> _parseCsvLine(String line, String delimiter) {
    final fields = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      final nextChar = i + 1 < line.length ? line[i + 1] : null;

      if (char == '"') {
        if (inQuotes && nextChar == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        fields.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }
    fields.add(current.toString().trim());
    return fields;
  }

  String _csvLine(List<String> fields, String delimiter) {
    return fields
        .map((field) {
          final escaped = field.replaceAll('"', '""');
          return '"$escaped"';
        })
        .join(delimiter);
  }

  Future<void> _importCsv() async {
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
      final importPath = await _pickImportPath();
      markStage('Datei auswählen');
      if (importPath == null) {
        importStopwatch.stop();
        return;
      }
      final content = await File(importPath).readAsString(encoding: utf8);
      markStage('Datei lesen');
      final cleaned = content.replaceFirst('\uFEFF', '');
      final lines = cleaned
          .split('\n')
          .map((line) => line.replaceAll('\r', ''))
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      if (lines.isEmpty) {
        importStopwatch.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV-Datei ist leer oder ungültig')),
          );
        }
        return;
      }
      final guessedDelimiter = lines.first.contains(';') ? ';' : ',';
      final csvRows = lines
          .map((line) => _parseCsvLine(line, guessedDelimiter))
          .toList(growable: false);
      markStage('CSV parsen');
      if (csvRows.isEmpty || csvRows.first.isEmpty) {
        importStopwatch.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV-Datei ist leer oder ungültig')),
          );
        }
        return;
      }

      final headers = csvRows.first
          .map((value) => _sanitizeHeader(value.toString()))
          .toList(growable: false);

      int? indexOf(List<String> aliases) {
        for (final alias in aliases) {
          final normalizedAlias = _sanitizeHeader(alias);
          final index = headers.indexOf(normalizedAlias);
          if (index >= 0) {
            return index;
          }
        }
        return null;
      }

      final dateIndex = indexOf(['datum', 'date']);
      final nameIndex = indexOf(['name']);
      final usageIndex = indexOf(['verwendung', 'usage']);
      final kat1Index = indexOf(['kat1', 'kategorie1', 'category1']);
      final kat2Index = indexOf(['kat2', 'kategorie2', 'category2']);
      final countryIndex = indexOf(['land', 'country']);
      final grossIndex = indexOf(['brutto', 'gross']);
      final vatRateIndex = indexOf(['mwstsatz', 'vatrate', 'taxrate']);
      final netIndex = indexOf(['netto', 'net']);
      final vatIndex = indexOf(['mwst', 'vat', 'tax']);

      String valueAt(List<String> row, int? index) {
        if (index == null || index < 0 || index >= row.length) {
          return '';
        }
        return row[index].trim();
      }

      var nextId = await _repository.nextId();
      var importedCount = 0;
      var skippedCount = 0;
      final importedRows = <IncomingInvoiceRow>[];

      for (var rowIndex = 1; rowIndex < csvRows.length; rowIndex++) {
        final row = csvRows[rowIndex];
        final isEmpty = row.every((value) => value.trim().isEmpty);
        if (isEmpty) {
          continue;
        }

        final date = valueAt(row, dateIndex);
        final name = valueAt(row, nameIndex);
        if (date.isEmpty || name.isEmpty) {
          skippedCount++;
          continue;
        }

        final gross = _parseAmount(valueAt(row, grossIndex));
        final vatRate = _parseAmount(valueAt(row, vatRateIndex));
        var net = _parseAmount(valueAt(row, netIndex));
        var vat = _parseAmount(valueAt(row, vatIndex));
        if (net == 0 && gross != 0) {
          net = gross / (1 + (vatRate / 100));
        }
        if (vat == 0 && gross != 0) {
          vat = gross - net;
        }

        final invoice = IncomingInvoiceRow(
          riId: nextId,
          riDate: date,
          riName: name,
          riUsage: valueAt(row, usageIndex),
          riKat1: valueAt(row, kat1Index),
          riKat2: valueAt(row, kat2Index),
          riCountry: valueAt(row, countryIndex),
          riGross: gross,
          riVatRate: vatRate,
          riNet: net,
          riVat: vat,
        );
        importedRows.add(invoice);
        nextId++;
        importedCount++;
      }
      markStage('Datensätze aufbereiten');

      await _repository.insertAll(importedRows);
      markStage('DB schreiben');
      _applyImportedRows(importedRows);
      markStage('UI aktualisieren');
      importStopwatch.stop();
      final elapsedMs = importStopwatch.elapsedMilliseconds;
      debugPrint(
        '⏱️ Rechnungseingang CSV-Import: $importedCount importiert, '
        '$skippedCount übersprungen in $elapsedMs ms | Top: '
        '${topStagesSummary()}',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV importiert: $importedCount Zeile(n), $skippedCount übersprungen '
            '($elapsedMs ms). Top: ${topStagesSummary()}',
          ),
        ),
      );
    } catch (error) {
      importStopwatch.stop();
      final elapsedMs = importStopwatch.elapsedMilliseconds;
      debugPrint(
        '⏱️ Rechnungseingang CSV-Import fehlgeschlagen nach $elapsedMs ms: '
        '$error | Top: ${topStagesSummary()}',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV-Import fehlgeschlagen nach $elapsedMs ms: $error '
            '(Top: ${topStagesSummary()})',
          ),
        ),
      );
    }
  }

  Future<void> _exportCsv() async {
    try {
      final rowsToExport = _visibleRows;
      if (rowsToExport.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Keine Zeilen zum Exportieren vorhanden'),
            ),
          );
        }
        return;
      }
      final fileName = 'rechnungseingang_${_timestamp(DateTime.now())}.csv';
      final exportPath = await _pickExportPath(fileName: fileName);
      if (exportPath == null) {
        return;
      }

      final delimiter = ';';
      final lines = <String>[
        _csvLine([
          'Datum',
          'Name',
          'Verwendung',
          'Kat1',
          'Kat2',
          'Land',
          'Brutto',
          'MwSt-Satz',
          'Netto',
          'MwSt',
        ], delimiter),
        for (final row in rowsToExport)
          _csvLine([
            row.riDate,
            row.riName,
            row.riUsage,
            row.riKat1,
            row.riKat2,
            row.riCountry,
            row.riGross.toStringAsFixed(2),
            row.riVatRate.toStringAsFixed(2),
            row.riNet.toStringAsFixed(2),
            row.riVat.toStringAsFixed(2),
          ], delimiter),
      ];
      final csvContent = lines.join('\n');
      await File(exportPath).writeAsString('\uFEFF$csvContent', encoding: utf8);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV exportiert: $exportPath')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV-Export fehlgeschlagen: $error')),
      );
    }
  }

  DataColumn2 _column(String label, int index, {double? fixedWidth}) =>
      DataColumn2(
        label: Text(
          label,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        onSort: _onSort,
        fixedWidth: fixedWidth,
      );

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

  DataCell _textCell(IncomingInvoiceRow row, String value) => DataCell(
    Tooltip(
      message: value.isEmpty ? '-' : value,
      child: Text(
        value.isEmpty ? '-' : value,
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.fade,
      ),
    ),
    onTap: () => setState(() => _selectedId = row.riId),
    onDoubleTap: () {
      setState(() => _selectedId = row.riId);
      _editSelectedRow();
    },
  );

  DataCell _moneyCell(IncomingInvoiceRow row, double value) {
    final text = value.toStringAsFixed(2).replaceAll('.', ',');
    return _textCell(row, text);
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;
    final hasSearch = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Rechnungseingang')),
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
                  onPressed: _loading ? null : _importCsv,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('CSV Import'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _exportCsv,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('CSV Export'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                labelText: 'Suche (Regex unterstützt)',
                hintText: 'z. B. ^2026-.*; oder Müller|Schmidt',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasSearch
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
            if (_searchRegexError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ungültiger Regex-Ausdruck: $_searchRegexError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                          headingRowHeight: 64,
                          dataRowHeight: 72,
                          showCheckboxColumn: false,
                          scrollController: _tableVerticalScrollController,
                          horizontalScrollController:
                              _tableHorizontalScrollController,
                          sortColumnIndex: _sortColumnIndex,
                          sortAscending: _sortAscending,
                          columns: [
                            _column('Datum', 0),
                            _column('Name', 1, fixedWidth: 240),
                            _column('Verwendung', 2, fixedWidth: 240),
                            _column('Kat1', 3, fixedWidth: 180),
                            _column('Kat2', 4, fixedWidth: 180),
                            _column('Land', 5),
                            _column('Brutto', 6),
                            _column('MwSt-Satz', 7),
                            _column('Netto', 8),
                            _column('MwSt', 9),
                          ],
                          rows: visibleRows
                              .map(
                                (row) => DataRow(
                                  selected: row.riId == _selectedId,
                                  onSelectChanged: (_) {
                                    setState(() => _selectedId = row.riId);
                                  },
                                  cells: [
                                    _textCell(row, row.riDate),
                                    _textCell(row, row.riName),
                                    _textCell(row, row.riUsage),
                                    _textCell(row, row.riKat1),
                                    _textCell(row, row.riKat2),
                                    _textCell(row, row.riCountry),
                                    _moneyCell(row, row.riGross),
                                    _moneyCell(row, row.riVatRate),
                                    _moneyCell(row, row.riNet),
                                    _moneyCell(row, row.riVat),
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
