import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
    'We deliver after having received the payment via bank transfer Total',
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

  List<OrderRow> _orders = [];
  Map<String, Customer> _customerById = {};
  List<Customer> _customers = [];
  String? _selectedOrderId;
  InvoiceDocumentData? _preview;

  bool _loadingOrders = true;
  bool _buildingPreview = false;
  bool _exportingPdf = false;
  String? _rememberedExportDirectory;
  bool _loadingRememberedExportDirectory = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedExportDirectory();
    _loadOrders();
  }

  Future<void> _loadRememberedExportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDirectory = prefs.getString(_lastExportDirectoryKey)?.trim();
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory =
          (savedDirectory == null || savedDirectory.isEmpty) ? null : savedDirectory;
      _loadingRememberedExportDirectory = false;
    });
  }

  @override
  void dispose() {
    _invoiceNoteController.dispose();
    super.dispose();
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
        for (final customer in customers) _normalizeIdToken(customer.cId): customer,
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auftraege konnten nicht geladen werden: $error')),
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
    return '${order.oId}_${token}_in';
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
                      .where((order) => _invoiceSearchText(order).contains(normalized))
                      .toList(growable: false);
                }
              });
            }

            return AlertDialog(
              title: const Text('Rechnung auswaehlen'),
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
                            subtitle: Text(order.oDate.trim().isEmpty ? '-' : order.oDate.trim()),
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
        for (final customer in customers) _normalizeIdToken(customer.cId): customer,
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auftraege konnten nicht aktualisiert werden: $error')),
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

  Future<void> _buildPreview() async {
    final orderId = _selectedOrderId;
    if (orderId == null || orderId.trim().isEmpty) {
      return;
    }

    setState(() {
      _buildingPreview = true;
    });

    try {
      final preview = await _documentBuilder.buildFromOrder(
        orderId: orderId,
        sellerProfile: _fixedSellerProfile,
        noteOverride: _invoiceNoteController.text.trim(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preview;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vorschau konnte nicht erzeugt werden: $error')),
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
      final targetPath = await _pickExportTargetPath(fileName: fileName);
      if (targetPath == null || targetPath.trim().isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export abgebrochen: Kein Speicherort ausgewaehlt.')),
        );
        return;
      }

      await File(targetPath).writeAsBytes(
        bytes,
        flush: true,
      );
      await _saveLastExportDirectory(targetPath);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rechnung gespeichert: $targetPath')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF-Export fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingPdf = false;
        });
      }
    }
  }

  Future<String?> _pickExportTargetPath({required String fileName}) async {
    final initialDirectory = await _resolveInitialExportDirectory();
    return FilePicker.saveFile(
      dialogTitle: 'Rechnung als PDF exportieren',
      fileName: fileName,
      initialDirectory: initialDirectory,
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
      lockParentWindow: true,
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

    final docsDir = await getApplicationDocumentsDirectory();
    return docsDir.path;
  }

  Future<void> _saveLastExportDirectory(String targetPath) async {
    final directory = p.dirname(targetPath).trim();
    if (directory.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastExportDirectoryKey, directory);
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory = directory;
    });
  }

  Future<void> _resetLastExportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastExportDirectoryKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _rememberedExportDirectory = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gemerkter Exportordner wurde zurueckgesetzt.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechnungen'),
        actions: [
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
                          ? 'Rechnung auswaehlen'
                          : _selectedInvoiceOrderLabel(),
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed:
                    (_buildingPreview || _selectedOrderId == null) ? null : _buildPreview,
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
                onPressed: (_exportingPdf || _preview == null) ? null : _exportPdf,
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF exportieren'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildRememberedDirectoryHint(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSellerCard(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildPreviewCard(),
                ),
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
            Text(
              'Verkäuferprofil',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _buildLockedValue('Firma', _fixedSellerProfile.company),
            const SizedBox(height: 8),
            _buildLockedValue('Strasse', _fixedSellerProfile.street),
            const SizedBox(height: 8),
            _buildLockedValue('Hausnummer', _fixedSellerProfile.houseNumber),
            const SizedBox(height: 8),
            _buildLockedValue('Ort', _fixedSellerProfile.city),
            const SizedBox(height: 8),
            _buildLockedValue('Land', _fixedSellerProfile.countryCode),
            const SizedBox(height: 8),
            _buildLockedValue('Phone', _fixedSellerProfile.phone),
            const SizedBox(height: 8),
            _buildLockedValue('E-Mail', _fixedSellerProfile.email),
            const SizedBox(height: 8),
            _buildLockedValue('Web', _fixedSellerProfile.web),
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
              'Optionale Hinweisbausteine',
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
    final label = (path == null || path.isEmpty) ? 'nicht gesetzt' : path;
    return Text(
      'Gemerkter Exportordner: $label',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _buildLockedValue(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: Text(value.trim().isEmpty ? '-' : value.trim()),
    );
  }

  Widget _buildPreviewCard() {
    final preview = _preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: preview == null
            ? const Center(
                child: Text('Keine Rechnungsvorschau vorhanden.'),
              )
            : ListView(
                children: [
                  Text(
                    'Vorschau',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _kv('Rechnungsnummer', preview.orderId),
                  _kv('Rechnungsdatum', preview.invoiceDate),
                  _kv('Auftrag', preview.orderId),
                  _kv('Währung', preview.currency),
                  _kv('Sprache', preview.language),
                  _kv('Preisart', _priceTypeLabel(preview.priceBasis)),
                  _kv('Kunde', _partyOneLine(preview.buyer)),
                  _kv('Positionen', preview.lines.length.toString()),
                  const Divider(height: 24),
                  Text(
                    'Summen',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _kv('Waren netto', _money(preview.totals.itemsNet, preview.currency)),
                  _kv('MwSt', _money(preview.totals.vatAmount, preview.currency)),
                  _kv('Waren brutto', _money(preview.totals.itemsGross, preview.currency)),
                  _kv('Versand', _money(preview.totals.shipping, preview.currency)),
                  _kv('PayPal-Gebühr', _money(preview.totals.paypalFee, preview.currency)),
                  const Divider(height: 24),
                  _kv(
                    'Gesamt',
                    _money(preview.totals.grandTotal, preview.currency),
                  ),
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

  void _applyNoteTemplate(String template) {
    final current = _invoiceNoteController.text.trim();
    if (current.isEmpty) {
      _invoiceNoteController.text = template;
      return;
    }

    final next = '$current\n$template';
    _invoiceNoteController.text = next;
    _invoiceNoteController.selection = TextSelection.collapsed(offset: next.length);
  }
}
