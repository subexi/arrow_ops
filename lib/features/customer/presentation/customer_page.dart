import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_path_config.dart';
import '../data/country_csv_service.dart';
import '../data/customer_csv_service.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'widgets/csv_import_preview_dialog.dart';
import 'widgets/customer_detail_dialog.dart';
import 'widgets/customer_form_dialog.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final CustomerRepository _repository = const CustomerRepository();
  final CustomerCsvService _csvService = CustomerCsvService();
  final CountryCsvService _countryCsvService = CountryCsvService();

  late final TextEditingController _searchController;

  bool _loading = false;
  List<Customer> _customers = const [];
  List<Customer> _filteredCustomers = const [];
  Map<String, String> _countryNameByCode = const {};
  String _databasePath = 'wird geladen...';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_filterCustomers);
    _loadDatabasePath();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDatabasePath() async {
    try {
      // Initialisiert die DB (inkl. Migration in den Zielordner),
      // die UI zeigt danach den konfigurierten Pfad an.
      await AppDatabase.instance.database;
      if (!mounted) {
        return;
      }
      setState(() => _databasePath = DatabasePathConfig.databasePath);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _databasePath = 'Pfad konnte nicht geladen werden');
    }
  }

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      final countries = await _repository.getAllCountries();
      final countryNameByCode = <String, String>{
        for (final country in countries) country.coTld.toLowerCase(): country.coName,
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _customers = customers;
        _countryNameByCode = countryNameByCode;
        _filterCustomers();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _filterCustomers() {
    final query = _searchController.text.toLowerCase().trim();

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() => _filteredCustomers = _customers);
      return;
    }

    final filtered = _customers.where((c) {
      return c.cId.toLowerCase().contains(query) ||
          c.cLastName.toLowerCase().contains(query) ||
          c.cFirstName.toLowerCase().contains(query) ||
          c.cCompany.toLowerCase().contains(query) ||
          c.cCityB.toLowerCase().contains(query) ||
          c.cCityD.toLowerCase().contains(query) ||
          c.cMail.toLowerCase().contains(query) ||
          c.cPhone.toLowerCase().contains(query) ||
          c.cStreetB.toLowerCase().contains(query) ||
          c.cStreetD.toLowerCase().contains(query) ||
          c.cPostalCodeB.toLowerCase().contains(query) ||
          c.cPostalCodeD.toLowerCase().contains(query) ||
          (c.cCountryBId?.toLowerCase().contains(query) ?? false) ||
          (c.cCountryDId?.toLowerCase().contains(query) ?? false);
    }).toList();

    if (!mounted) return;
    setState(() => _filteredCustomers = filtered);
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

  Future<void> _importCsv() async {
    setState(() => _loading = true);
    try {
      debugPrint('📂 Öffne FilePicker...');
      final initialDirectory = await _defaultPickerDirectory();
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
        dialogTitle: 'CSV-Datei zum Importieren auswählen',
        initialDirectory: initialDirectory,
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('⊘ FilePicker: Keine Datei ausgewählt');
        return;
      }

      final file = result.files.single;
      debugPrint('✅ Datei ausgewählt: ${file.name} (${file.size} bytes)');
      
      final content = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();

      debugPrint('📖 Datei gelesen: ${content.length} Zeichen');
      await _processImport(content);
    } catch (error, stackTrace) {
      debugPrint('❌ FilePicker-Fehler: $error');
      debugPrint('📍 Stack: $stackTrace');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dateiauswahl fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _processImport(String content) async {
    final customers = _csvService.importCustomers(content);

    if (!mounted) {
      return;
    }

    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine gültigen Kundendaten in der Datei gefunden.')),
      );
      return;
    }

    // Validiere Kundendaten
    final validCustomers = <Customer>[];
    final invalidRows = <int>[];

    for (int i = 0; i < customers.length; i++) {
      final c = customers[i];
      if (c.cId.isEmpty || c.cLastName.isEmpty || c.cFirstName.isEmpty) {
        invalidRows.add(i);
      } else {
        validCustomers.add(c);
      }
    }

    if (invalidRows.isNotEmpty) {
      debugPrint('⚠️ ${invalidRows.length} ungültige Reihen: $invalidRows');
    }

    if (validCustomers.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine gültigen Kundendaten nach Validierung gefunden.')),
      );
      return;
    }

    // Zeige Vorschau
    if (!mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => CsvImportPreviewDialog(
        customers: validCustomers,
        onConfirm: () async {
          await _performImport(validCustomers);
        },
      ),
    );
  }

  Future<void> _performImport(List<Customer> customers) async {
    setState(() => _loading = true);
    try {
      debugPrint('🔄 Starte Import von ${customers.length} Kundendatensätzen...');
      debugPrint('📋 Erste Kundin: ${customers.isNotEmpty ? customers.first.cLastName : "keine"}');
      
      final inserted = await _repository.bulkUpsert(customers);
      
      debugPrint('✅ Import erfolgreich: $inserted Datensätze');

      await _loadCustomers();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$inserted Kundendatensätze importiert.')),
      );
    } catch (error, stackTrace) {
      debugPrint('⚠️ Import-Fehler: $error');
      debugPrint('📍 Stack: $stackTrace');
      debugPrint('Type: ${error.runtimeType}');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import fehlgeschlagen: $error')),
      );
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
      final csv = _csvService.exportCustomers(customers);
      final initialDirectory = await _defaultPickerDirectory();

      final fileName =
          'customer_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

      String? targetPath;

      if (Platform.isMacOS) {
        targetPath = await FilePicker.saveFile(
          dialogTitle: 'CSV exportieren',
          fileName: fileName,
          initialDirectory: initialDirectory,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        );
      }

      targetPath ??= p.join((await getApplicationDocumentsDirectory()).path, fileName);

      await File(targetPath).writeAsString(csv);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exportiert nach: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $error')),
      );
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
        dialogTitle: 'country_tld.csv auswählen',
        initialDirectory: initialDirectory,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw Exception('Dateipfad konnte nicht gelesen werden.');
      }

      final content = await File(path).readAsString();
      final countries = _countryCsvService.importCountries(content);

      if (countries.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine gültigen Länder in country_tld.csv gefunden.')),
        );
        return;
      }

      final inserted = await _repository.bulkUpsertCountries(countries);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$inserted Länder importiert.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('country_tld Import fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createCustomer() async {
    final countries = await _repository.getAllCountries();
    if (!mounted) return;

    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => CustomerFormDialog(countries: countries),
    );

    if (result == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      debugPrint('➕ Erstelle neuen Kundendatensatz: ${result.cId}');
      await _repository.upsert(result);
      debugPrint('✅ Kunde erstellt: ${result.cLastName}, ${result.cFirstName}');
      
      await _loadCustomers();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde erstellt: ${result.cLastName}, ${result.cFirstName}')),
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Erstellen: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Erstellen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editCustomer(Customer customer) async {
    final countries = await _repository.getAllCountries();
    if (!mounted) return;

    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => CustomerFormDialog(customer: customer, countries: countries),
    );

    if (result == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      debugPrint('✏️ Aktualisiere Kundendatensatz: ${result.cId}');
      await _repository.update(result);
      debugPrint('✅ Kunde aktualisiert: ${result.cLastName}, ${result.cFirstName}');
      
      await _loadCustomers();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde aktualisiert: ${result.cLastName}, ${result.cFirstName}')),
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Aktualisieren: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Aktualisieren: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    setState(() => _loading = true);
    try {
      debugPrint('🗑️ Lösche Kundendatensatz: ${customer.cId}');
      await _repository.delete(customer.cId);
      debugPrint('✅ Kunde gelöscht: ${customer.cLastName}, ${customer.cFirstName}');
      
      await _loadCustomers();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde gelöscht: ${customer.cLastName}, ${customer.cFirstName}')),
      );
    } catch (error) {
      debugPrint('❌ Fehler beim Löschen: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Löschen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrow Ops - Customer'),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Buttons
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Tooltip(
                  message: 'Erstellt einen neuen Kundendatensatz.',
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _createCustomer,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Neuer Kunde'),
                  ),
                ),
                Tooltip(
                  message: 'Exportiert alle Kunden als CSV-Datei.',
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _exportCsv,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('CSV exportieren'),
                  ),
                ),
                Tooltip(
                  message: 'Importiert Länder-Codes aus country_tld.csv.',
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _importCountryCsv,
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('country_tld.csv importieren'),
                  ),
                ),
                Tooltip(
                  message: 'Lädt die Kundenliste neu aus der SQLite-Datenbank.',
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _loadCustomers,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Aktualisieren'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              'SQLite: $_databasePath',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // Search Field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Kundendaten durchsuchen...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV importieren',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Tooltip(
                      message: 'Öffnet den Dateidialog zum Import von customer.csv.',
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _importCsv,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('customer.csv auswählen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Customer List
            Text(
              _searchController.text.isEmpty
                  ? 'Kundendaten (${_customers.length})'
                  : 'Kundendaten (${_filteredCustomers.length} von ${_customers.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? const Center(
                          child: Text('Noch keine Kundendaten vorhanden.'),
                        )
                      : _filteredCustomers.isEmpty
                          ? const Center(
                              child: Text('Keine Kunden gefunden, die dem Suchbegriff entsprechen.'),
                            )
                          : ListView.separated(
                              itemCount: _filteredCustomers.length,
                              separatorBuilder: (_, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = _filteredCustomers[index];
                                return ListTile(
                                  dense: true,
                                  title: Text('${c.cLastName}, ${c.cFirstName}'),
                                  subtitle: Text(
                                    '${c.cCompany} | ${c.cCityB} | ${c.cMail}',
                                  ),
                                  trailing: Text(c.cId),
                                  onTap: _loading ? null : () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => CustomerDetailDialog(
                                        customer: c,
                                        countryNameByCode: _countryNameByCode,
                                        onEdit: () => _editCustomer(c),
                                        onDelete: () => _deleteCustomer(c),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
