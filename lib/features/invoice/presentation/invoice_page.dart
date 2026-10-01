import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../customer/data/customer_repository.dart';
import '../../customer/domain/customer.dart';
import '../../order/data/order_repository.dart';
import '../../order/domain/invoice_models.dart';
import '../../order/domain/order_models.dart';
import '../data/invoice_document_build_service.dart';
import '../data/invoice_pdf_service.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  static const _lastExportDirectoryKey = 'invoice_last_export_directory';
  static const List<String> _noteTemplates = <String>[
    'Versand erfolgt nach Zahlungseingang',
    'Versand erfolgt nach Zahlungseingang per Banküberweisung',
    'We deliver after having received the payment',
    'We deliver after having received the payment via bank transfer',
    'Zur Beachtung bei Benutzung des Arrow-Fix:\nSchaftdurchmesser vor Bearbeitung prüfen und ggf. durch Schleifen anpassen\nWenn Schaftdurchmesser zu groß ist, kann durch die entstehende Reibungswärme das Werkzeug Schaden nehmen',
    'Important notes when using the Arrow-Fix:\nCheck the shank diameter before machining and adjust it by grinding if necessary.\nIf the shank diameter is too large, the resulting frictional heat may damage the tool.',
  ];
  static const InvoiceSellerProfile _fixedSellerProfile = InvoiceSellerProfile(
    company: 'Arrow-Engineering UG',
    street: 'Lange Furche',
    houseNumber: '13',
    postalCode: '70736',
    city: 'Fellbach',
    countryCode: 'Germany',
    email: 'sales@arrow-fix.com',
    phone: '+49 171 53 86 301',
    web: 'www.arrow-fix.com',
  );

  final _orderRepository = const OrderRepository();
  final _customerRepository = const CustomerRepository();
  final _documentBuilder = InvoiceDocumentBuildService();
  final _pdfService = const InvoicePdfService();

  final _invoiceNoteController = TextEditingController();
  final _documentDateController = TextEditingController();
  final _exportDirectoryController = TextEditingController();

  List<OrderRow> _orders = [];
  Map<String, Customer> _customerById = {};
  List<Customer> _customers = [];
  String? _selectedOrderId;
  InvoiceDocumentData? _preview;
  InvoiceDocumentKind _selectedDocumentKind = InvoiceDocumentKind.invoice;
  InvoiceDocumentKind? _previewDocumentKind;
  bool _isProforma = false;

  bool _loadingOrders = true;
  bool _buildingPreview = false;
  bool _exportingPdf = false;
  String? _rememberedExportDirectory;
  String? _fallbackExportDirectory;
  bool _loadingRememberedExportDirectory = true;

  @override
  void initState() {
    super.initState();
    _documentDateController.text = _todayIsoDate();
    _loadRememberedExportDirectory();
    _loadOrders();
  }

  Future<void> _loadRememberedExportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDirectory = prefs.getString(_lastExportDirectoryKey)?.trim();
    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackDirectory = p.join(docsDir.path, 'pdf_exports');
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory =
          (savedDirectory == null || savedDirectory.isEmpty)
          ? null
          : savedDirectory;
      _fallbackExportDirectory = fallbackDirectory;
      _exportDirectoryController.text = _rememberedExportDirectory ?? '';
      _loadingRememberedExportDirectory = false;
    });
  }

  @override
  void dispose() {
    _invoiceNoteController.dispose();
    _documentDateController.dispose();
    _exportDirectoryController.dispose();
    super.dispose();
  }

  String _todayIsoDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<void> _pickDocumentDate() async {
    final currentText = _documentDateController.text.trim();
    final initialDate = DateTime.tryParse(currentText) ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null || !mounted) {
      return;
    }
    final month = selected.month.toString().padLeft(2, '0');
    final day = selected.day.toString().padLeft(2, '0');
    setState(() {
      _documentDateController.text = '${selected.year}-$month-$day';
    });
    await _buildPreview(documentKind: _selectedDocumentKind);
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loadingOrders = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        _orderRepository.getOrders(),
        _customerRepository.getAll(),
      ]);
      final orders = results[0] as List<OrderRow>;
      final customers = results[1] as List<Customer>;
      final customerById = <String, Customer>{
        for (final customer in customers)
          _normalizeIdToken(customer.cId): customer,
      };
      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _customers = customers;
        _customerById = customerById;
        if (_selectedOrderId == null && orders.isNotEmpty) {
          _selectedOrderId = orders.first.oId;
        }
      });

      if (_selectedOrderId != null) {
        await _buildPreview();
      }
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: 'Auftraege konnten nicht geladen werden',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingOrders = false;
        });
      }
    }
  }

  String _invoiceOrderLabel(OrderRow order) {
    final customer = _resolveCustomer(order);
    final lastName = customer?.cLastName.trim() ?? '';
    final token = _normalizedNameToken(lastName);
    final suffix = _selectedDocumentKind == InvoiceDocumentKind.packingList
        ? 'pl'
        : 'in';
    return '${order.oId}_${token}_$suffix';
  }

  String _invoiceSearchText(OrderRow order) {
    final customer = _resolveCustomer(order);
    final lastName = customer?.cLastName.trim().toLowerCase() ?? '';
    return '${order.oId.toLowerCase()} $lastName ${_invoiceOrderLabel(order).toLowerCase()}';
  }

  String _selectedInvoiceOrderLabel() {
    final selectedId = _selectedOrderId;
    if (selectedId == null) {
      return '-';
    }
    final selectedOrder = _orders.cast<OrderRow?>().firstWhere(
      (order) => order?.oId == selectedId,
      orElse: () => null,
    );
    if (selectedOrder == null) {
      return selectedId;
    }
    return _invoiceOrderLabel(selectedOrder);
  }

  Future<OrderRow?> _showOrderPickerDialog() async {
    if (_orders.isEmpty) {
      return null;
    }

    return showDialog<OrderRow>(
      context: context,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        var filtered = List<OrderRow>.from(_orders);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyFilter(String query) {
              final normalized = query.trim().toLowerCase();
              setDialogState(() {
                if (normalized.isEmpty) {
                  filtered = List<OrderRow>.from(_orders);
                } else {
                  filtered = _orders
                      .where(
                        (order) =>
                            _invoiceSearchText(order).contains(normalized),
                      )
                      .toList(growable: false);
                }
              });
            }

            return AlertDialog(
              title: const Text('Dokument auswaehlen'),
              content: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Suche',
                        hintText: 'Nummer oder Kunde eingeben...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: applyFilter,
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return ListTile(
                            dense: true,
                            title: Text(_invoiceOrderLabel(order)),
                            subtitle: Text(
                              order.oDate.trim().isEmpty
                                  ? '-'
                                  : order.oDate.trim(),
                            ),
                            onTap: () => Navigator.of(dialogContext).pop(order),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Abbrechen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _refreshOrdersForSelection() async {
    try {
      final results = await Future.wait<dynamic>([
        _orderRepository.getOrders(),
        _customerRepository.getAll(),
      ]);
      final orders = results[0] as List<OrderRow>;
      final customers = results[1] as List<Customer>;
      final customerById = <String, Customer>{
        for (final customer in customers)
          _normalizeIdToken(customer.cId): customer,
      };

      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
        _customers = customers;
        _customerById = customerById;
        final selected = _selectedOrderId;
        if (selected == null || !orders.any((order) => order.oId == selected)) {
          _selectedOrderId = orders.isEmpty ? null : orders.first.oId;
        }
      });
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: 'Auftraege konnten nicht aktualisiert werden',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Customer? _resolveCustomer(OrderRow order) {
    final normalizedOrderCustomerId = _normalizeIdToken(order.oCustomerId);
    final direct = _customerById[normalizedOrderCustomerId];
    if (direct != null) {
      return direct;
    }

    final orderNumeric = _numericId(order.oCustomerId);
    if (orderNumeric == null) {
      return null;
    }

    for (final customer in _customers) {
      final candidate = _numericId(customer.cId);
      if (candidate != null && candidate == orderNumeric) {
        return customer;
      }
    }
    return null;
  }

  String _normalizeIdToken(String raw) {
    return raw.trim().toLowerCase();
  }

  int? _numericId(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }

  String _normalizedNameToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return 'Unbekannt';
    }
    final clean = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) {
      return 'Unbekannt';
    }
    return clean;
  }

  Future<void> _buildPreview({InvoiceDocumentKind? documentKind}) async {
    final orderId = _selectedOrderId;
    if (orderId == null || orderId.trim().isEmpty) {
      return;
    }

    final targetKind = documentKind ?? _selectedDocumentKind;

    setState(() {
      _buildingPreview = true;
    });

    try {
      final preview = await _documentBuilder.buildFromOrder(
        orderId: orderId,
        documentKind: targetKind,
        isProforma: _isProforma,
        sellerProfile: _fixedSellerProfile,
        invoiceDate: _documentDateController.text.trim().isEmpty
            ? null
            : _documentDateController.text.trim(),
        noteOverride: _invoiceNoteController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preview;
        _previewDocumentKind = targetKind;
      });
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: 'Vorschau konnte nicht erzeugt werden',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _buildingPreview = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    await _exportPdfForKind(_selectedDocumentKind);
  }

  Future<void> _exportPdfForKind(InvoiceDocumentKind kind) async {
    if (_preview == null || _previewDocumentKind != kind) {
      await _buildPreview(documentKind: kind);
    }

    final preview = _preview;
    if (preview == null) {
      return;
    }

    setState(() {
      _exportingPdf = true;
    });

    try {
      final bytes = await _pdfService.generatePdfBytes(preview);
      final fileName = _pdfService.buildDefaultFileName(preview);
      final targetPath = await _pickExportTargetPath(
        fileName: fileName,
        documentKind: kind,
      );
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.'),
          ),
        );
        return;
      }

      final savedPath = await _writePdfWithFallback(
        bytes: bytes,
        preferredPath: targetPath,
        fileName: fileName,
      );
      await _saveLastExportDirectory(savedPath);

      if (!mounted) {
        return;
      }

      final documentName = kind == InvoiceDocumentKind.packingList
          ? 'Lieferschein'
          : 'Rechnung';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$documentName gespeichert: $savedPath')),
      );
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        title: 'PDF-Export fehlgeschlagen',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingPdf = false;
        });
      }
    }
  }

  Future<String?> _pickExportTargetPath({
    required String fileName,
    required InvoiceDocumentKind documentKind,
  }) async {
    final exportDirectory = await _resolveInitialExportDirectory();
    return _nextAvailablePath(
      directoryPath: exportDirectory,
      fileName: fileName,
    );
  }

  Future<String> _resolveInitialExportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDirectory = prefs.getString(_lastExportDirectoryKey)?.trim();
    if (savedDirectory != null && savedDirectory.isNotEmpty) {
      final savedDir = Directory(savedDirectory);
      if (await savedDir.exists()) {
        return savedDirectory;
      }
    }
    return _ensureFallbackExportDirectory();
  }

  Future<void> _saveLastExportDirectory(String targetPath) async {
    final directory = p.dirname(targetPath).trim();
    if (directory.isEmpty) {
      return;
    }

    await _setRememberedExportDirectory(directory);
  }

  Future<void> _setRememberedExportDirectory(String directory) async {
    final normalizedDirectory = directory.trim();
    if (normalizedDirectory.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastExportDirectoryKey, normalizedDirectory);
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory = normalizedDirectory;
      _exportDirectoryController.text = normalizedDirectory;
    });
  }

  Future<String> _writePdfWithFallback({
    required List<int> bytes,
    required String preferredPath,
    required String fileName,
  }) async {
    final normalizedPreferredPath = preferredPath.trim();
    try {
      final preferredDirectory = Directory(p.dirname(normalizedPreferredPath));
      await preferredDirectory.create(recursive: true);
      await File(normalizedPreferredPath).writeAsBytes(bytes, flush: true);
      return normalizedPreferredPath;
    } on FileSystemException {
      final fallbackDirectory = await _ensureFallbackExportDirectory();
      final fallbackPath = await _nextAvailablePath(
        directoryPath: fallbackDirectory,
        fileName: fileName,
      );
      await File(fallbackPath).writeAsBytes(bytes, flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Konnte nicht am ausgewaehlten Ort speichern. Fallback verwendet: $fallbackPath',
            ),
          ),
        );
      }

      return fallbackPath;
    }
  }

  Future<String> _ensureFallbackExportDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackDirectory = Directory(p.join(docsDir.path, 'pdf_exports'));
    await fallbackDirectory.create(recursive: true);
    return fallbackDirectory.path;
  }

  Future<String> _nextAvailablePath({
    required String directoryPath,
    required String fileName,
  }) async {
    final extension = p.extension(fileName);
    final baseName = p.basenameWithoutExtension(fileName);
    var candidatePath = p.join(directoryPath, fileName);
    var counter = 1;
    while (await File(candidatePath).exists()) {
      candidatePath = p.join(directoryPath, '$baseName($counter)$extension');
      counter++;
    }
    return candidatePath;
  }

  Future<void> _resetLastExportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastExportDirectoryKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory = null;
      _exportDirectoryController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gemerkter Exportordner wurde zurueckgesetzt.'),
      ),
    );
  }

  Future<void> _openExportDirectoryInFinder() async {
    final configuredDirectory = _rememberedExportDirectory?.trim() ?? '';
    final fallbackDirectory = (await getApplicationDocumentsDirectory()).path;
    final directory = configuredDirectory.isEmpty
        ? fallbackDirectory
        : configuredDirectory;

    final exists = await Directory(directory).exists();
    if (!exists) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ordner nicht gefunden: $directory')),
      );
      return;
    }

    final result = await Process.run('open', [directory]);
    if (!mounted) {
      return;
    }

    if (result.exitCode == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ordner im Finder geoeffnet: $directory')),
      );
      return;
    }

    final stderrText = (result.stderr ?? '').toString().trim();
    final suffix = stderrText.isEmpty ? '' : ' ($stderrText)';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ordner konnte nicht geoeffnet werden$suffix')),
    );
  }

  Future<void> _pickExportDirectory() async {
    String? selectedPath;
    try {
      selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Exportordner für PDFs auswählen',
      );
    } on PlatformException catch (error, stackTrace) {
      final entitlementBlocked = error.code.toUpperCase().contains(
        'ENTITLEMENT_REQUIRED',
      );
      if (entitlementBlocked) {
        final appleScriptPath = await _pickDirectoryViaAppleScript();
        if (appleScriptPath != null && appleScriptPath.trim().isNotEmpty) {
          await _setExportDirectory(appleScriptPath);
          return;
        }

        final fallbackDirectory = await _ensureFallbackExportDirectory();
        await _setRememberedExportDirectory(fallbackDirectory);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ordnerdialog hat keine Berechtigung. Exportordner wurde auf App-Ordner gesetzt: $fallbackDirectory',
            ),
          ),
        );
        return;
      }

      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: 'Exportordner konnte nicht ausgewählt werden',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      if (Platform.isMacOS) {
        final appleScriptPath = await _pickDirectoryViaAppleScript();
        if (appleScriptPath != null && appleScriptPath.trim().isNotEmpty) {
          await _setExportDirectory(appleScriptPath);
        }
      }
      return;
    }

    await _setExportDirectory(selectedPath);
  }

  Future<String?> _pickDirectoryViaAppleScript() async {
    if (!Platform.isMacOS) {
      return null;
    }

    final result = await Process.run('osascript', [
      '-e',
      'try',
      '-e',
      'set chosenFolder to choose folder with prompt "Exportordner fuer PDFs auswaehlen"',
      '-e',
      'POSIX path of chosenFolder',
      '-e',
      'on error number -128',
      '-e',
      'return ""',
      '-e',
      'end try',
    ]);

    if (result.exitCode != 0) {
      return null;
    }

    final output = (result.stdout ?? '').toString().trim();
    return output.isEmpty ? null : output;
  }

  Future<void> _setExportDirectoryFromInput() async {
    final candidate = _exportDirectoryController.text.trim();
    if (candidate.isEmpty) {
      return;
    }
    await _setExportDirectory(candidate);
  }

  Future<void> _setExportDirectory(String directoryPath) async {
    final normalized = directoryPath.trim();
    if (normalized.isEmpty) {
      return;
    }

    try {
      final directory = Directory(normalized);
      await directory.create(recursive: true);
      final probeFile = File(
        p.join(
          normalized,
          '.arrow_ops_write_probe_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probeFile.writeAsString('probe', flush: true);
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
      if (!mounted) {
        return;
      }

      await _setRememberedExportDirectory(normalized);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportordner gesetzt: $normalized')),
      );
    } on FileSystemException catch (error, stackTrace) {
      final fallbackDirectory = await _ensureFallbackExportDirectory();
      await _setRememberedExportDirectory(fallbackDirectory);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ausgewählter Ordner nicht beschreibbar. App-Ordner gesetzt: $fallbackDirectory',
          ),
        ),
      );
      await _showErrorDialog(
        title: 'Exportordner konnte nicht direkt gesetzt werden',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechnungen / Lieferscheine'),
        actions: [
          IconButton(
            onPressed: _openExportDirectoryInFinder,
            tooltip: 'Exportordner im Finder oeffnen',
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            onPressed: _resetLastExportDirectory,
            tooltip: 'Exportordner zuruecksetzen',
            icon: const Icon(Icons.folder_delete_outlined),
          ),
          IconButton(
            onPressed: _loadingOrders ? null : _loadOrders,
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingOrders
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 520,
                child: OutlinedButton.icon(
                  onPressed: _orders.isEmpty
                      ? null
                      : () async {
                          await _refreshOrdersForSelection();
                          final selectedOrder = await _showOrderPickerDialog();
                          if (selectedOrder == null || !mounted) {
                            return;
                          }
                          setState(() {
                            _selectedOrderId = selectedOrder.oId;
                          });
                          await _buildPreview();
                        },
                  icon: const Icon(Icons.search),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _selectedOrderId == null
                          ? 'Dokument auswaehlen'
                          : _selectedInvoiceOrderLabel(),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Proforma',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Aktiv: Proforma Rechnung / Proforma invoice',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _isProforma,
                        onChanged: (value) async {
                          setState(() {
                            _isProforma = value;
                          });
                          await _buildPreview(
                            documentKind: _selectedDocumentKind,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: SegmentedButton<InvoiceDocumentKind>(
                  segments: const [
                    ButtonSegment<InvoiceDocumentKind>(
                      value: InvoiceDocumentKind.invoice,
                      label: Text('Rechnung'),
                    ),
                    ButtonSegment<InvoiceDocumentKind>(
                      value: InvoiceDocumentKind.packingList,
                      label: Text('Lieferschein'),
                    ),
                  ],
                  selected: <InvoiceDocumentKind>{_selectedDocumentKind},
                  onSelectionChanged: (selection) async {
                    if (selection.isEmpty) {
                      return;
                    }
                    final selected = selection.first;
                    if (_selectedDocumentKind == selected) {
                      return;
                    }
                    setState(() {
                      _selectedDocumentKind = selected;
                    });
                    await _buildPreview(documentKind: selected);
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: (_buildingPreview || _selectedOrderId == null)
                    ? null
                    : _buildPreview,
                icon: _buildingPreview
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined),
                label: const Text('Vorschau aktualisieren'),
              ),
              FilledButton.icon(
                onPressed: (_exportingPdf || _preview == null)
                    ? null
                    : _exportPdf,
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _selectedDocumentKind == InvoiceDocumentKind.packingList
                      ? 'Lieferschein exportieren'
                      : 'Rechnung exportieren',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildExportDirectoryControls(),
          const SizedBox(height: 8),
          _buildRememberedDirectoryHint(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSellerCard()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildPreviewCard()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Verkäuferprofil',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _copySellerProfileToClipboard,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Kopieren'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSellerProfileBlock(),
            const SizedBox(height: 8),
            TextField(
              controller: _documentDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Datum rechts (PDF)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Datum wählen',
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: _pickDocumentDate,
                ),
              ),
              onTap: _pickDocumentDate,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  setState(() {
                    _documentDateController.text = _todayIsoDate();
                  });
                  await _buildPreview(documentKind: _selectedDocumentKind);
                },
                icon: const Icon(Icons.today_outlined),
                label: const Text('Heute setzen'),
              ),
            ),
            const Divider(height: 24),
            TextField(
              controller: _invoiceNoteController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Lieferhinweis',
                hintText: 'Optionaler Lieferhinweis',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Optionale Hinweisbausteine (frei kombinierbar)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _noteTemplates
                  .map(
                    (template) => ActionChip(
                      label: Text(template),
                      onPressed: () => _applyNoteTemplate(template),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRememberedDirectoryHint() {
    if (_loadingRememberedExportDirectory) {
      return Text(
        'Gemerkter Exportordner: wird geladen...',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final path = _rememberedExportDirectory;
    final fallbackPath = _fallbackExportDirectory;
    final hasPath = path != null && path.isNotEmpty;
    final isFallbackActive =
        hasPath &&
        fallbackPath != null &&
        fallbackPath.isNotEmpty &&
        p.equals(path, fallbackPath);
    final statusText = !hasPath
        ? 'kein Exportordner gesetzt'
        : (isFallbackActive ? 'Fallback-Ordner aktiv' : 'Benutzerordner aktiv');
    final label = hasPath ? path : 'nicht gesetzt';

    final statusColor = !hasPath
        ? Theme.of(context).colorScheme.outline
        : (isFallbackActive ? Colors.orange.shade700 : Colors.green.shade700);
    final statusIcon = !hasPath
        ? Icons.info_outline
        : (isFallbackActive
              ? Icons.warning_amber_outlined
              : Icons.check_circle_outline);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(statusIcon, size: 18, color: statusColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Status: $statusText\nGemerkter Exportordner: $label',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExportDirectoryControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _exportDirectoryController,
                decoration: const InputDecoration(
                  labelText: 'PDF-Ablageordner',
                  hintText: '/Pfad/zum/Ordner',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _setExportDirectoryFromInput(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _setExportDirectoryFromInput,
              child: const Text('Pfad setzen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _pickExportDirectory,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Exportordner waehlen'),
            ),
            OutlinedButton.icon(
              onPressed: _openExportDirectoryInFinder,
              icon: const Icon(Icons.open_in_new_outlined),
              label: const Text('Im Finder oeffnen'),
            ),
            OutlinedButton.icon(
              onPressed: _resetLastExportDirectory,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Exportordner zuruecksetzen'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSellerProfileBlock() {
    final profileText = _sellerProfileText();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        profileText,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  String _sellerProfileText() {
    String valueOrDash(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? '-' : trimmed;
    }

    final lines = <String>[
      valueOrDash(_fixedSellerProfile.company),
      '${valueOrDash(_fixedSellerProfile.street)} ${valueOrDash(_fixedSellerProfile.houseNumber)}',
      '${valueOrDash(_fixedSellerProfile.postalCode)} ${valueOrDash(_fixedSellerProfile.city)}',
      valueOrDash(_fixedSellerProfile.countryCode),
      'Phone: ${valueOrDash(_fixedSellerProfile.phone)}',
      'E-Mail: ${valueOrDash(_fixedSellerProfile.email)}',
      'Web: ${valueOrDash(_fixedSellerProfile.web)}',
    ];

    return lines.join('\n');
  }

  Future<void> _copySellerProfileToClipboard() async {
    final profileText = _sellerProfileText();
    await Clipboard.setData(ClipboardData(text: profileText));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Verkaeuferprofil kopiert.')));
  }

  Widget _buildPreviewCard() {
    final preview = _preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: preview == null
            ? const Center(child: Text('Keine Dokumentvorschau vorhanden.'))
            : ListView(
                children: [
                  Text(
                    'Vorschau',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _kv('Dokumentnummer', preview.orderId),
                  _kv('Dokumentdatum', preview.invoiceDate),
                  _kv('Auftrag', preview.orderId),
                  _kv('Währung', preview.currency),
                  _kv('Sprache', preview.language),
                  _kv('Proforma', preview.isProforma ? 'ja' : 'nein'),
                  _kv('Preisart', _priceTypeLabel(preview.priceBasis)),
                  _kv('Kunde', _partyOneLine(preview.buyer)),
                  _kv('Positionen', preview.lines.length.toString()),
                  _kv(
                    'Warengewicht',
                    _weight(preview.totals.totalWeightInGram),
                  ),
                  if (preview.documentKind == InvoiceDocumentKind.invoice) ...[
                    const Divider(height: 24),
                    Text(
                      'Summen',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _kv(
                      'Waren netto',
                      _money(preview.totals.itemsNet, preview.currency),
                    ),
                    _kv(
                      'MwSt',
                      _money(preview.totals.vatAmount, preview.currency),
                    ),
                    _kv(
                      'Waren brutto',
                      _money(preview.totals.itemsGross, preview.currency),
                    ),
                    if (!_hideShippingAndPayPalForProforma(preview))
                      _kv(
                        'Versand',
                        _money(preview.totals.shipping, preview.currency),
                      ),
                    if (!_hideShippingAndPayPalForProforma(preview))
                      _kv(
                        'PayPal-Gebühr',
                        _money(preview.totals.paypalFee, preview.currency),
                      ),
                    const Divider(height: 24),
                    _kv(
                      'Gesamt',
                      _money(_displayGrandTotal(preview), preview.currency),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _partyOneLine(InvoicePartyData party) {
    final parts = <String>[];
    if (party.company.trim().isNotEmpty && party.company.trim() != '-') {
      parts.add(party.company.trim());
    }
    if (party.name.trim().isNotEmpty && party.name.trim() != '-') {
      parts.add(party.name.trim());
    }
    return parts.isEmpty ? '-' : parts.join(' | ');
  }

  String _money(double value, String currency) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} $currency';
  }

  String _weight(double grams) {
    if (grams < 1000) {
      return '${grams.toStringAsFixed(0).replaceAll('.', ',')} g';
    }
    final kilograms = grams / 1000;
    return '${kilograms.toStringAsFixed(2).replaceAll('.', ',')} kg';
  }

  String _priceTypeLabel(String priceBasis) {
    final normalized = priceBasis.trim().toLowerCase();
    if (normalized == 'gross') {
      return 'brutto';
    }
    if (normalized == 'net') {
      return 'netto';
    }
    return priceBasis;
  }

  bool _hideShippingAndPayPalForProforma(InvoiceDocumentData data) {
    return data.documentKind == InvoiceDocumentKind.invoice && data.isProforma;
  }

  double _displayGrandTotal(InvoiceDocumentData data) {
    if (!_hideShippingAndPayPalForProforma(data)) {
      return data.totals.grandTotal;
    }
    final adjusted =
        data.totals.grandTotal - data.totals.shipping - data.totals.paypalFee;
    return adjusted < 0 ? 0 : adjusted;
  }

  Future<void> _showErrorDialog({
    required String title,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    if (!mounted) {
      return;
    }

    final details = StringBuffer(error.toString());
    if (stackTrace != null) {
      final stackLines = stackTrace
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(8)
          .join('\n');
      if (stackLines.isNotEmpty) {
        details
          ..write('\n\nStacktrace:\n')
          ..write(stackLines);
      }
    }

    final detailText = details.toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: SelectableText(detailText)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: detailText));
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fehlerdetails kopiert')),
                );
              },
              child: const Text('Details kopieren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schliessen'),
            ),
          ],
        );
      },
    );
  }

  void _applyNoteTemplate(String template) {
    final current = _invoiceNoteController.text.trim();
    if (current.isEmpty) {
      _invoiceNoteController.text = template;
      return;
    }

    final next = '$current\n$template';
    _invoiceNoteController.text = next;
    _invoiceNoteController.selection = TextSelection.collapsed(
      offset: next.length,
    );
  }
}
