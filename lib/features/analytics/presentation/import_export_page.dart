import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../customer/data/country_csv_service.dart';
import '../../customer/data/customer_csv_service.dart';
import '../../customer/data/customer_repository.dart';
import '../../customer/domain/country_tld.dart';
import '../../customer/domain/customer.dart';
import '../../customer/presentation/widgets/csv_import_preview_dialog.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  final CustomerRepository _repository = const CustomerRepository();
  final CustomerCsvService _customerCsvService = CustomerCsvService();
  final CountryCsvService _countryCsvService = CountryCsvService();

  static final RegExp _validCountryCodePattern = RegExp(r'^[a-z]{2,}$');

  bool _loading = false;

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<String?> _defaultPickerDirectory() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (await docs.exists()) {
        return docs.path;
      }
    } catch (_) {
      // Fallback to platform default dialog location.
    }
    return null;
  }

  Future<void> _importCsv({bool replaceExisting = false}) async {
    setState(() => _loading = true);
    try {
      final initialDirectory = await _defaultPickerDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        dialogTitle: 'CSV-Datei zum Importieren auswaehlen',
        initialDirectory: initialDirectory,
      );

      if (result.isEmpty) {
        return;
      }

      final file = result.single;
      final content = file.path != null
          ? await File(file.path!).readAsString()
          : utf8.decode(await file.readAsBytes());

      await _processImport(content, replaceExisting: replaceExisting);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFeedback('Dateiauswahl fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importCsvWithReplacement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bestand vor Import loeschen?'),
        content: const Text(
          'Der bestehende Kundenbestand wird vor dem Import vollstaendig geloescht. Fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Loeschen und importieren'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _importCsv(replaceExisting: true);
  }

  Future<void> _processImport(
    String content, {
    bool replaceExisting = false,
  }) async {
    final customers = _customerCsvService.importCustomers(content);

    if (!mounted) {
      return;
    }

    if (customers.isEmpty) {
      _showFeedback('Keine gueltigen Kundendaten in der Datei gefunden.');
      return;
    }

    final validCustomers = <Customer>[];
    for (final customer in customers) {
      if (customer.cId.isEmpty ||
          customer.cLastName.isEmpty ||
          customer.cFirstName.isEmpty) {
        continue;
      }
      validCustomers.add(customer);
    }

    if (validCustomers.isEmpty) {
      _showFeedback('Keine gueltigen Kundendaten nach Validierung gefunden.');
      return;
    }

    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CsvImportPreviewDialog(
        customers: validCustomers,
        replaceExisting: replaceExisting,
        onConfirm: () async {
          await _performImport(
            validCustomers,
            replaceExisting: replaceExisting,
          );
        },
      ),
    );
  }

  Future<void> _performImport(
    List<Customer> customers, {
    bool replaceExisting = false,
  }) async {
    setState(() => _loading = true);
    try {
      var deleted = 0;
      if (replaceExisting) {
        deleted = await _repository.deleteAllCustomers();
      }

      final inserted = await _repository.bulkUpsert(customers);

      _showFeedback(
        replaceExisting
            ? '$inserted Kundendatensaetze importiert, $deleted alte Datensaetze geloescht.'
            : '$inserted Kundendatensaetze importiert.',
      );
    } catch (error) {
      _showFeedback('Import fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      final csv = _customerCsvService.exportCustomers(customers);
      final initialDirectory = await _defaultPickerDirectory();

      final fileName =
          'customer_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

      String? targetPath;

      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'CSV exportieren',
          fileName: fileName,
          bytes: Uint8List(0),
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );

      await File(targetPath).writeAsString(csv);
      _showFeedback('CSV exportiert nach: $targetPath');
    } catch (error) {
      _showFeedback('Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _countryNameFromDeliveryCode(
    String? countryCode,
    Map<String, String> countryNameByCode,
  ) {
    final normalized = countryCode?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == '-') {
      return '';
    }
    return countryNameByCode[normalized] ?? normalized.toUpperCase();
  }

  String _buildFileTimestamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    final month = twoDigits(value.month);
    final day = twoDigits(value.day);
    final hour = twoDigits(value.hour);
    final minute = twoDigits(value.minute);
    final second = twoDigits(value.second);
    return '$year$month${day}_$hour$minute$second';
  }

  Future<void> _exportLocationsCsv() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      final countries = await _repository.getAllCountries();
      final countryNameByCode = <String, String>{
        for (final country in countries)
          country.coTld.toLowerCase(): country.coName,
      };

      final buffer = StringBuffer('street,zip,city,country,lat,lon\n');
      final lastRowByAddress = <String, String>{};
      for (final customer in customers) {
        final street =
            '${customer.cStreetD.trim()} ${customer.cHouseNumberD.trim()}'.trim();
        final zip = customer.cPostalCodeD.trim();
        final city = customer.cCityD.trim();
        final country = _countryNameFromDeliveryCode(
          customer.cCountryDId,
          countryNameByCode,
        );
        final lat = customer.cLat.toString();
        final lon = customer.cLon.toString();
        final addressKey =
            '${street.toLowerCase()}|${zip.toLowerCase()}|${city.toLowerCase()}';

        lastRowByAddress[addressKey] =
            '${_csvEscape(street)},${_csvEscape(zip)},${_csvEscape(city)},${_csvEscape(country)},${_csvEscape(lat)},${_csvEscape(lon)}';
      }

      for (final row in lastRowByAddress.values) {
        buffer.writeln(row);
      }

      final initialDirectory = await _defaultPickerDirectory();
      final fileName =
          'af_locations_${_buildFileTimestamp(DateTime.now())}.csv';

      String? targetPath;
      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'Customers locations als CSV exportieren',
          fileName: fileName,
          bytes: Uint8List(0),
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );
      await File(targetPath).writeAsString(buffer.toString());
      _showFeedback('Locations-CSV exportiert nach: $targetPath');
    } catch (error) {
      _showFeedback('Locations-Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCountryCsv() async {
    setState(() => _loading = true);
    try {
      final countries = await _repository.getAllCountries();
      final exportedCodes = <String>{};
      final buffer = StringBuffer('co_tld,co_name\n');
      for (final country in countries) {
        final tld = country.coTld.trim().toLowerCase();
        if (!_validCountryCodePattern.hasMatch(tld)) {
          continue;
        }
        if (!exportedCodes.add(tld)) {
          continue;
        }
        final name = country.coName.trim();
        buffer.writeln('${_csvEscape(tld)},${_csvEscape(name)}');
      }

      final fileName =
          'country_tld_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
      final initialDirectory = await _defaultPickerDirectory();

      String? targetPath;
      if (Platform.isMacOS) {
        targetPath = (await FilePicker.saveFile(
          dialogTitle: 'Laender als CSV exportieren',
          fileName: fileName,
          bytes: Uint8List(0),
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        ))?.toFilePath();
      }

      targetPath ??= p.join(
        (await getApplicationDocumentsDirectory()).path,
        fileName,
      );
      await File(targetPath).writeAsString(buffer.toString());
      _showFeedback('Laender-CSV exportiert nach: $targetPath');
    } catch (error) {
      _showFeedback('Laender-Export fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cleanupInvalidCountriesWithPreview() async {
    setState(() => _loading = true);
    try {
      final countries = await _repository.getAllCountries();
      final customers = await _repository.getAll();

      final referencedCodes = <String>{
        for (final c in customers)
          ...[
            c.cCountryBId?.trim().toLowerCase() ?? '',
            c.cCountryDId?.trim().toLowerCase() ?? '',
          ].where((code) => code.isNotEmpty),
      };

      final invalidCountries = countries
          .where((country) {
            final code = country.coTld.trim().toLowerCase();
            return !_validCountryCodePattern.hasMatch(code);
          })
          .toList()
        ..sort(
          (a, b) => a.coTld.toLowerCase().compareTo(b.coTld.toLowerCase()),
        );

      if (!mounted) {
        return;
      }

      if (invalidCountries.isEmpty) {
        _showFeedback('Keine ungueltigen Laender-Codes gefunden.');
        return;
      }

      final deletable = <CountryTld>[];
      final blocked = <CountryTld>[];

      for (final country in invalidCountries) {
        final code = country.coTld.trim().toLowerCase();
        if (referencedCodes.contains(code)) {
          blocked.add(country);
        } else {
          deletable.add(country);
        }
      }

      String formatCountries(List<CountryTld> entries) {
        if (entries.isEmpty) {
          return '-';
        }
        return entries
            .map(
              (entry) =>
                  '${entry.coTld.trim().toLowerCase()} (${entry.coName.trim()})',
            )
            .join('\n');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ungueltige Laender-Codes bereinigen'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gefunden: ${invalidCountries.length} ungueltige Eintraege'),
                const SizedBox(height: 10),
                Text('Werden geloescht (${deletable.length}):'),
                const SizedBox(height: 4),
                Text(
                  formatCountries(deletable),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nicht loeschbar wegen Kundenreferenzen (${blocked.length}):',
                ),
                const SizedBox(height: 4),
                Text(
                  formatCountries(blocked),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: deletable.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Loeschen'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      final deleted = await _repository.deleteCountriesByCodes(
        deletable.map((entry) => entry.coTld).toList(),
      );

      _showFeedback(
        '$deleted ungueltige Laender geloescht. ${blocked.length} waren referenziert und wurden uebersprungen.',
      );
    } catch (error) {
      _showFeedback('Bereinigung fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importCountryCsv() async {
    setState(() => _loading = true);
    try {
      final initialDirectory = await _defaultPickerDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        dialogTitle: 'country_tld.csv auswaehlen',
        initialDirectory: initialDirectory,
      );

      if (result.isEmpty) {
        return;
      }

      final file = result.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw Exception('Dateipfad konnte nicht gelesen werden.');
      }

      final content = await File(path).readAsString();
      final countries = _countryCsvService.importCountries(content);

      if (countries.isEmpty) {
        _showFeedback('Keine gueltigen Laender in country_tld.csv gefunden.');
        return;
      }

      final inserted = await _repository.bulkUpsertCountries(countries);
      _showFeedback('$inserted Laender importiert.');
    } catch (error) {
      _showFeedback('country_tld Import fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import / Export',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Datenaktionen fuer Kunden und Laender.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kunden',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _importCsv,
                        icon: const Icon(Icons.upload),
                        label: const Text('Kunden aus CSV importieren'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _importCsvWithReplacement,
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Kunden importieren (Bestand loeschen)'),
                      ),
                      FilledButton.icon(
                        onPressed: _loading ? null : _exportCsv,
                        icon: const Icon(Icons.download),
                        label: const Text('Kunden exportieren'),
                      ),
                      FilledButton.icon(
                        onPressed: _loading ? null : _exportLocationsCsv,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Kunden-Standorte exportieren'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Laender',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _importCountryCsv,
                        icon: const Icon(Icons.upload),
                        label: const Text('Laender importieren'),
                      ),
                      FilledButton.icon(
                        onPressed: _loading ? null : _exportCountryCsv,
                        icon: const Icon(Icons.download),
                        label: const Text('Laender exportieren'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _cleanupInvalidCountriesWithPreview,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Ungueltige Laender bereinigen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
