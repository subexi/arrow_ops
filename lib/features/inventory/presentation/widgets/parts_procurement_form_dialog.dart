import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../item/domain/item_models.dart';
import '../../domain/parts_procurement_models.dart';

class PartsProcurementFormDialog extends StatefulWidget {
  const PartsProcurementFormDialog({
    super.key,
    required this.nextId,
    required this.catalogueItems,
    this.initialValue,
  });

  final int nextId;
  final List<ItemCatalogueRow> catalogueItems;
  final PartsProcurementRow? initialValue;

  @override
  State<PartsProcurementFormDialog> createState() => _PartsProcurementFormDialogState();
}

class _PartsProcurementFormDialogState extends State<PartsProcurementFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _purchaseDateController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceNetController;
  late final TextEditingController _totalPriceNetController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _pointOfUseController;
  late final TextEditingController _partSourceController;
  late final TextEditingController _materialController;
  late final TextEditingController _noteController;
  late final TextEditingController _drawingController;

  late final Map<String, String> _descriptionByIdi;
  late final List<String> _idiOptions;
  String _selectedIdi = '';

  bool get _isWide => MediaQuery.of(context).size.width >= 760;

  @override
  void initState() {
    super.initState();

    final descriptions = <String, String>{};
    for (final item in widget.catalogueItems) {
      final idi = item.icIdi.trim();
      if (idi.isEmpty) {
        continue;
      }
      descriptions.putIfAbsent(idi, () => item.icDescriptionDeLong.trim());
    }
    _descriptionByIdi = descriptions;
    _idiOptions = descriptions.keys.toList(growable: false)..sort((a, b) => a.compareTo(b));

    final initial = widget.initialValue;
    _selectedIdi = initial?.ppIdi ?? (_idiOptions.isEmpty ? '' : _idiOptions.first);

    _purchaseDateController = TextEditingController(text: initial?.ppPurchaseDate ?? '');
    _quantityController = TextEditingController(text: (initial?.ppQuantity ?? 0).toString());
    _priceNetController = TextEditingController(text: _decimalText(initial?.ppPriceNet));
    _totalPriceNetController = TextEditingController(text: _decimalText(initial?.ppTotalPriceNet));
    _descriptionController = TextEditingController(
      text: initial?.ppDescriptionDeLong ?? _descriptionByIdi[_selectedIdi] ?? '',
    );
    _pointOfUseController = TextEditingController(text: initial?.ppPointOfUse ?? '');
    _partSourceController = TextEditingController(text: initial?.ppPartSource ?? '');
    _materialController = TextEditingController(text: initial?.ppMaterial ?? '');
    _noteController = TextEditingController(text: initial?.ppNote ?? '');
    _drawingController = TextEditingController(text: initial?.ppDrawing ?? '');

    _quantityController.addListener(_recalculateTotalPrice);
    _priceNetController.addListener(_recalculateTotalPrice);
    _recalculateTotalPrice();
  }

  @override
  void dispose() {
    _purchaseDateController.dispose();
    _quantityController.dispose();
    _priceNetController.dispose();
    _totalPriceNetController.dispose();
    _descriptionController.dispose();
    _pointOfUseController.dispose();
    _partSourceController.dispose();
    _materialController.dispose();
    _noteController.dispose();
    _drawingController.dispose();
    super.dispose();
  }

  static String _decimalText(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _text(TextEditingController controller) => controller.text.trim();

  int _parseInt(TextEditingController controller) => int.tryParse(_text(controller)) ?? 0;

  double _parseDouble(TextEditingController controller) =>
      double.tryParse(_text(controller).replaceAll(',', '.')) ?? 0;

  void _recalculateTotalPrice() {
    final quantity = _parseInt(_quantityController);
    final priceNet = _parseDouble(_priceNetController);
    final total = quantity * priceNet;
    final totalText = total.toStringAsFixed(2).replaceAll('.', ',');
    if (_totalPriceNetController.text == totalText) {
      return;
    }
    _totalPriceNetController.text = totalText;
  }

  Future<void> _pickDrawingFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'dwg',
        'dxf',
        'svg',
        'png',
        'jpg',
        'jpeg',
        'webp',
      ],
    );

    final selectedPath = result?.files.single.path?.trim() ?? '';
    if (selectedPath.isEmpty) {
      return;
    }

    setState(() {
      _drawingController.text = selectedPath;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
      locale: const Locale('de'),
    );
    if (picked == null) {
      return;
    }
    final dateText =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => _purchaseDateController.text = dateText);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (label == 'Bezeichnung' && (value == null || value.trim().isEmpty)) {
          return 'Bitte Bezeichnung wählen';
        }
        return null;
      },
    );
  }

  Widget _row(List<Widget> children) {
    if (!_isWide) {
      return Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final row = PartsProcurementRow(
      ppId: widget.initialValue?.ppId ?? widget.nextId,
      ppIdi: _selectedIdi,
      ppPurchaseDate: _text(_purchaseDateController),
      ppQuantity: _parseInt(_quantityController),
      ppPriceNet: _parseDouble(_priceNetController),
      ppTotalPriceNet: _parseDouble(_totalPriceNetController),
      ppDescriptionDeLong: _text(_descriptionController),
      ppPointOfUse: _text(_pointOfUseController),
      ppPartSource: _text(_partSourceController),
      ppMaterial: _text(_materialController),
      ppNote: _text(_noteController),
      ppDrawing: _text(_drawingController),
    );
    Navigator.of(context).pop(row);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Bestand anlegen' : 'Bestand bearbeiten'),
      content: SizedBox(
        width: 900,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedIdi.isEmpty ? null : _selectedIdi,
                  decoration: const InputDecoration(
                    labelText: 'Bezeichnung',
                    border: OutlineInputBorder(),
                  ),
                  items: _idiOptions
                      .map(
                        (idi) => DropdownMenuItem<String>(
                          value: idi,
                          child: Text(idi),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedIdi = value;
                      _descriptionController.text = _descriptionByIdi[value] ?? '';
                    });
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bitte Bezeichnung wählen';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _row([
                  _field(
                    _purchaseDateController,
                    'Beschaffungsdatum',
                    readOnly: true,
                    onTap: _pickDate,
                  ),
                  _field(
                    _quantityController,
                    'Menge in Stk',
                    keyboardType: TextInputType.number,
                  ),
                  _field(
                    _priceNetController,
                    'EK netto / Stk',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ]),
                const SizedBox(height: 12),
                _field(
                  _totalPriceNetController,
                  'Gesamt EK netto',
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                _field(
                  _descriptionController,
                  'Beschreibung',
                  maxLines: 3,
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                _row([
                  _field(_pointOfUseController, 'Verwendung'),
                  _field(_partSourceController, 'Lieferant'),
                ]),
                const SizedBox(height: 12),
                _field(_materialController, 'Materialbeschreibung'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _drawingController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Zeichnung',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Datei wählen',
                      onPressed: _pickDrawingFile,
                      icon: const Icon(Icons.attach_file),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _field(_noteController, 'Notiz', maxLines: 3),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
