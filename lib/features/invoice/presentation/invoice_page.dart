import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final _orderRepository = const OrderRepository();
  final _documentBuilder = InvoiceDocumentBuildService();
  final _pdfService = const InvoicePdfService();

  final _sellerNameController = TextEditingController(text: 'Arrow Ops');
  final _sellerCompanyController = TextEditingController(text: 'Arrow Ops');
  final _sellerStreetController = TextEditingController();
  final _sellerHouseNumberController = TextEditingController();
  final _sellerPostalCodeController = TextEditingController();
  final _sellerCityController = TextEditingController();
  final _sellerCountryController = TextEditingController(text: 'DE');
  final _sellerVatIdController = TextEditingController();
  final _sellerEmailController = TextEditingController();
  final _sellerPhoneController = TextEditingController();

  List<OrderRow> _orders = [];
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
    _sellerNameController.dispose();
    _sellerCompanyController.dispose();
    _sellerStreetController.dispose();
    _sellerHouseNumberController.dispose();
    _sellerPostalCodeController.dispose();
    _sellerCityController.dispose();
    _sellerCountryController.dispose();
    _sellerVatIdController.dispose();
    _sellerEmailController.dispose();
    _sellerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loadingOrders = true;
    });

    try {
      final orders = await _orderRepository.getOrders();
      if (!mounted) {
        return;
      }

      setState(() {
        _orders = orders;
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

  InvoiceSellerProfile _sellerProfileFromForm() {
    return InvoiceSellerProfile(
      name: _sellerNameController.text.trim(),
      company: _sellerCompanyController.text.trim(),
      street: _sellerStreetController.text.trim(),
      houseNumber: _sellerHouseNumberController.text.trim(),
      postalCode: _sellerPostalCodeController.text.trim(),
      city: _sellerCityController.text.trim(),
      countryCode: _sellerCountryController.text.trim(),
      vatId: _sellerVatIdController.text.trim(),
      email: _sellerEmailController.text.trim(),
      phone: _sellerPhoneController.text.trim(),
    );
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
        sellerProfile: _sellerProfileFromForm(),
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
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _orders.any((o) => o.oId == _selectedOrderId)
                      ? _selectedOrderId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Auftrag',
                  ),
                  items: _orders
                      .map(
                        (order) => DropdownMenuItem<String>(
                          value: order.oId,
                          child: Text('${order.oId} (${order.oDate})'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) async {
                    setState(() {
                      _selectedOrderId = value;
                    });
                    await _buildPreview();
                  },
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
              'Verkaeuferprofil',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            _buildTextField(_sellerNameController, 'Name'),
            const SizedBox(height: 8),
            _buildTextField(_sellerCompanyController, 'Firma'),
            const SizedBox(height: 8),
            _buildTextField(_sellerStreetController, 'Strasse'),
            const SizedBox(height: 8),
            _buildTextField(_sellerHouseNumberController, 'Hausnummer'),
            const SizedBox(height: 8),
            _buildTextField(_sellerPostalCodeController, 'PLZ'),
            const SizedBox(height: 8),
            _buildTextField(_sellerCityController, 'Ort'),
            const SizedBox(height: 8),
            _buildTextField(_sellerCountryController, 'Land (Code)'),
            const SizedBox(height: 8),
            _buildTextField(_sellerVatIdController, 'VAT ID'),
            const SizedBox(height: 8),
            _buildTextField(_sellerEmailController, 'E-Mail'),
            const SizedBox(height: 8),
            _buildTextField(_sellerPhoneController, 'Telefon'),
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

  Widget _buildTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) {
        // keep preview stale-safe and force explicit regenerate to avoid expensive rebuild per key stroke
      },
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
                  _kv('Rechnungsnummer', preview.invoiceNumber),
                  _kv('Rechnungsdatum', preview.invoiceDate),
                  _kv('Auftrag', preview.orderId),
                  _kv('Waehrung', preview.currency),
                  _kv('Sprache', preview.language),
                  _kv('Preisbasis', preview.priceBasis),
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
                  _kv('PayPal-Gebuehr', _money(preview.totals.paypalFee, preview.currency)),
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
}
