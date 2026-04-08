import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/customer_csv_service.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final CustomerRepository _repository = const CustomerRepository();
  final CustomerCsvService _csvService = CustomerCsvService();

  bool _loading = false;
  List<Customer> _customers = const [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loading = true);
    try {
      final customers = await _repository.getAll();
      if (!mounted) {
        return;
      }
      setState(() => _customers = customers);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _importCsv() async {
    setState(() => _loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final content = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();

      final customers = _csvService.importCustomers(content);
      final inserted = await _repository.bulkUpsert(customers);

      await _loadCustomers();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$inserted Kundendatensatze importiert.')),
      );
    } catch (error) {
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

      final fileName =
          'customer_export_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

      String? targetPath;

      if (Platform.isMacOS) {
        targetPath = await FilePicker.platform.saveFile(
          dialogTitle: 'CSV exportieren',
          fileName: fileName,
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _importCsv,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('CSV importieren'),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _exportCsv,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('CSV exportieren'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loadCustomers,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Aktualisieren'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Datensatze: ${_customers.length}'),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? const Center(child: Text('Noch keine Kundendaten vorhanden.'))
                      : ListView.separated(
                          itemCount: _customers.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = _customers[index];
                            return ListTile(
                              dense: true,
                              title: Text('${c.cLastName}, ${c.cFirstName}'),
                              subtitle: Text(
                                '${c.cCompany} | ${c.cCityB} | ${c.cMail}',
                              ),
                              trailing: Text(c.cId),
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
