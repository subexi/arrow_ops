import 'dart:io';

import 'package:flutter/material.dart';

import '../../../item/data/item_image_storage_service.dart';
import '../../../item/domain/item_models.dart';
import '../../domain/order_models.dart';

class ItemOrderedFormDialog extends StatefulWidget {
  const ItemOrderedFormDialog({
    super.key,
    required this.orderId,
    required this.orderLanguage,
    required this.orderPriceBasis,
    required this.isDealerCustomer,
    required this.availableItems,
    required this.initialPos,
    this.initialValue,
  });

  final String orderId;
  final String orderLanguage;
  final String orderPriceBasis;
  final bool isDealerCustomer;
  final List<ItemCatalogueRow> availableItems;
  final int initialPos;
  final ItemOrderedRow? initialValue;

  @override
  State<ItemOrderedFormDialog> createState() => _ItemOrderedFormDialogState();
}

class _ItemOrderedFormDialogState extends State<ItemOrderedFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imageStorage = const ItemImageStorageService();
  final _discountFocusNode = FocusNode();

  late final TextEditingController _orderIdController;
  late final TextEditingController _posController;
  late final TextEditingController _idiSearchController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _htsController;
  late final TextEditingController _colorController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _discountController;
  late final TextEditingController _totalPriceController;
  late final TextEditingController _itemWeightController;
  late final TextEditingController _totalWeightController;
  late final TextEditingController _photoController;

  int? _selectedItemId;
  bool _expandDescription = false;
  bool _isApplyingCalculatedUnitPrice = false;
  double? _baseUnitPriceBeforeDiscount;

  static const double _grossFactor = 1.19;

  bool get _isEditing => widget.initialValue != null;
  bool get _isOrderLanguageDe => widget.orderLanguage.trim().toUpperCase() == 'DE';

  ItemCatalogueRow? _catalogueItemById(int? itemId) {
    if (itemId == null) {
      return null;
    }
    return widget.availableItems.cast<ItemCatalogueRow?>().firstWhere(
          (item) => item?.icId == itemId,
          orElse: () => null,
        );
  }

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;

    _orderIdController = TextEditingController(text: v?.ioOrderId ?? widget.orderId);
    _posController = TextEditingController(text: (v?.ioPos ?? widget.initialPos).toString().padLeft(2, '0'));
    _idiSearchController = TextEditingController(text: v?.ioIdi ?? '');
    _descriptionController = TextEditingController(
      text: _isOrderLanguageDe
          ? (v?.ioDescriptionDeLong ?? '')
          : (v?.ioDescriptionEnLong ?? ''),
    );
    _htsController = TextEditingController(text: v?.ioHts ?? '-');
    _colorController = TextEditingController(text: v?.ioColor ?? '-');
    _quantityController = TextEditingController(text: (v?.ioQuantity ?? 1).toString());
    _unitPriceController = TextEditingController(text: _decimalText(v?.ioUnitPrice ?? 0));
    _discountController = TextEditingController(text: _discountText(v?.ioDiscount ?? 0));
    _totalPriceController = TextEditingController(text: _decimalText(v?.ioTotalPrice ?? 0));
    _itemWeightController = TextEditingController(text: _weightText(v?.ioItemWeight ?? 0));
    _totalWeightController = TextEditingController(text: _weightText(v?.ioTotalWeight ?? 0));
    _photoController = TextEditingController(text: v?.ioPhoto ?? '-');

    _selectedItemId = v?.ioItemId;

    final initiallySelectedItem = _catalogueItemById(_selectedItemId);
    if (initiallySelectedItem != null) {
      _htsController.text = initiallySelectedItem.icHts.trim().isEmpty
        ? '-'
        : initiallySelectedItem.icHts.trim();
      _photoController.text = initiallySelectedItem.icImagePath.trim().isEmpty
        ? '-'
        : initiallySelectedItem.icImagePath.trim();

      _baseUnitPriceBeforeDiscount = _catalogueUnitPrice(initiallySelectedItem);
      _applyDiscountToUnitPrice();
    } else {
      final initialDiscount = _parseDiscountPercent();
      final initialEffectiveUnitPrice = _parseDecimal(_unitPriceController);
      _baseUnitPriceBeforeDiscount = _deriveBaseUnitPrice(
        effectiveUnitPrice: initialEffectiveUnitPrice,
        discountPercent: initialDiscount,
      );
    }

    _quantityController.addListener(_recalculateTotals);
    _unitPriceController.addListener(_onUnitPriceChanged);
    _discountController.addListener(_onDiscountChanged);
    _itemWeightController.addListener(_recalculateTotals);
    _discountFocusNode.addListener(_normalizeDiscountOnBlur);

    _recalculateTotals();
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    _posController.dispose();
    _idiSearchController.dispose();
    _descriptionController.dispose();
    _htsController.dispose();
    _colorController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    _discountController.dispose();
    _totalPriceController.dispose();
    _itemWeightController.dispose();
    _totalWeightController.dispose();
    _photoController.dispose();
    _discountFocusNode.dispose();
    super.dispose();
  }

  String _decimalText(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  String _weightText(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

  String _discountText(double value) => _roundToOneDecimal(value).toStringAsFixed(1).replaceAll('.', ',');

  double _roundToOneDecimal(double value) => (value * 10).round() / 10;

  int _parseInt(TextEditingController controller, {int fallback = 0}) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  double _parseDecimal(TextEditingController controller, {double fallback = 0}) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? fallback;

  double _parseDiscountPercent() {
    final parsed = _parseDecimal(_discountController);
    return parsed.clamp(0.0, 100.0).toDouble();
  }

  double _deriveBaseUnitPrice({
    required double effectiveUnitPrice,
    required double discountPercent,
  }) {
    if (discountPercent <= 0 || discountPercent >= 100) {
      return effectiveUnitPrice;
    }
    return effectiveUnitPrice / (1 - (discountPercent / 100));
  }

  double _grossPrice(double netPrice) => netPrice * _grossFactor;

  double _catalogueUnitPrice(ItemCatalogueRow item) {
    if (widget.isDealerCustomer) {
      return item.icPriceWholesaleNet;
    }

    final basis = widget.orderPriceBasis.trim().toLowerCase();
    if (basis == 'gross') {
      return _grossPrice(item.icPriceNet);
    }
    return item.icPriceNet;
  }

  void _setUnitPriceText(double value) {
    final unitPriceText = _decimalText(value);
    if (_unitPriceController.text == unitPriceText) {
      return;
    }

    _isApplyingCalculatedUnitPrice = true;
    _unitPriceController
      ..text = unitPriceText
      ..selection = TextSelection.collapsed(offset: unitPriceText.length);
    _isApplyingCalculatedUnitPrice = false;
  }

  void _applyDiscountToUnitPrice() {
    final base = _baseUnitPriceBeforeDiscount ?? _parseDecimal(_unitPriceController);
    final discountPercent = _parseDiscountPercent();
    final discountAmount = base * (discountPercent / 100);
    final reducedUnitPrice = (base - discountAmount).clamp(0.0, double.infinity).toDouble();

    _setUnitPriceText(reducedUnitPrice);
    _recalculateTotals();
  }

  void _onUnitPriceChanged() {
    if (_isApplyingCalculatedUnitPrice) {
      _recalculateTotals();
      return;
    }

    final currentUnitPrice = _parseDecimal(_unitPriceController);
    final discountPercent = _parseDiscountPercent();
    _baseUnitPriceBeforeDiscount = _deriveBaseUnitPrice(
      effectiveUnitPrice: currentUnitPrice,
      discountPercent: discountPercent,
    );
    _recalculateTotals();
  }

  void _onDiscountChanged() {
    final discountPercent = _parseDiscountPercent();
    _baseUnitPriceBeforeDiscount ??= _deriveBaseUnitPrice(
      effectiveUnitPrice: _parseDecimal(_unitPriceController),
      discountPercent: discountPercent,
    );

    _applyDiscountToUnitPrice();
  }

  void _normalizeDiscountOnBlur() {
    if (_discountFocusNode.hasFocus) {
      return;
    }

    final normalized = _discountText(_parseDiscountPercent());
    if (_discountController.text == normalized) {
      return;
    }

    _discountController
      ..text = normalized
      ..selection = TextSelection.collapsed(offset: normalized.length);
  }

  double _currentDiscountAmount() {
    final discountPercent = _parseDiscountPercent();
    if (discountPercent <= 0) {
      return 0;
    }

    final baseUnitPrice = _baseUnitPriceBeforeDiscount ?? _parseDecimal(_unitPriceController);
    return baseUnitPrice * (discountPercent / 100);
  }

  Widget _buildDiscountAmountHint() {
    return AnimatedBuilder(
      animation: Listenable.merge([_unitPriceController, _discountController]),
      builder: (context, child) {
        final discountAmount = _currentDiscountAmount();
        if (discountAmount <= 0) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Rabattbetrag pro Einheit: ${_decimalText(discountAmount)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }

  void _recalculateTotals() {
    final quantity = _parseInt(_quantityController, fallback: 1);
    final unitPrice = _parseDecimal(_unitPriceController);
    final itemWeight = _parseDecimal(_itemWeightController);

    final totalPrice = quantity * unitPrice;
    final totalWeight = quantity * itemWeight;

    final totalPriceText = _decimalText(totalPrice);
    final totalWeightText = _weightText(totalWeight);

    if (_totalPriceController.text != totalPriceText) {
      _totalPriceController.text = totalPriceText;
    }
    if (_totalWeightController.text != totalWeightText) {
      _totalWeightController.text = totalWeightText;
    }
  }

  void _onItemSelected(int? itemId) {
    setState(() {
      _selectedItemId = itemId;
      final selected = widget.availableItems.cast<ItemCatalogueRow?>().firstWhere(
            (item) => item?.icId == itemId,
            orElse: () => null,
          );
      if (selected == null) {
        _idiSearchController.clear();
        return;
      }

      _idiSearchController.text = selected.icIdi;
      _baseUnitPriceBeforeDiscount = _catalogueUnitPrice(selected);
      _applyDiscountToUnitPrice();
      _itemWeightController.text = _weightText(selected.icWeight);
      _htsController.text = selected.icHts.trim().isEmpty ? '-' : selected.icHts.trim();
      _photoController.text = selected.icImagePath.trim().isEmpty ? '-' : selected.icImagePath.trim();

      if (_isOrderLanguageDe) {
        _descriptionController.text = selected.icDescriptionDeLong;
      } else {
        _descriptionController.text = selected.icDescriptionEnLong;
      }

      _recalculateTotals();
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool readOnly = false,
    int? maxLines = 1,
    String? Function(String?)? validator,
    VoidCallback? onTap,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      readOnly: readOnly,
      maxLines: maxLines,
      validator: validator,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _row2(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildPhotoPreview() {
    final photoPath = _photoController.text.trim();
    if (photoPath.isEmpty || photoPath == '-') {
      return const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: _imageStorage.resolveAbsolutePath(photoPath),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data?.trim();
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return const SizedBox.shrink();
        }

        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return const SizedBox.shrink();
        }

        return Tooltip(
          message: 'Klicken zum Vergroessern',
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showPhotoDialog(file),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPhotoDialog(File file) async {
    final transformController = TransformationController();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 860,
          height: 560,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTap: () {
                    transformController.value = Matrix4.identity();
                  },
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 0.6,
                    maxScale: 5,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Text('Bild konnte nicht geladen werden.'),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Schliessen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    transformController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Position bearbeiten' : 'Neue Position'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row2(
                  _field(_orderIdController, 'io_order_id', readOnly: true),
                  _field(_posController, 'io_pos', readOnly: true),
                ),
                const SizedBox(height: 12),
                DropdownMenu<int>(
                  controller: _idiSearchController,
                  initialSelection: _selectedItemId,
                  width: 720,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  label: const Text('Bezeichnung'),
                  dropdownMenuEntries: [
                    for (final item in widget.availableItems)
                      DropdownMenuEntry<int>(
                        value: item.icId,
                        label: '${item.icIdi} • ${item.icId}',
                      ),
                  ],
                  onSelected: _onItemSelected,
                ),
                if (_selectedItemId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Bitte einen Artikel auswählen.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _field(
                  _descriptionController,
                  'Beschreibung',
                  maxLines: _expandDescription ? null : 4,
                  onTap: () {
                    if (_expandDescription) {
                      return;
                    }
                    setState(() => _expandDescription = true);
                  },
                ),
                const SizedBox(height: 12),
                _row2(
                  _field(_htsController, 'HTS Code', readOnly: true),
                  _field(_colorController, 'Farbe'),
                ),
                const SizedBox(height: 12),
                _field(_photoController, 'Bild', readOnly: true),
                const SizedBox(height: 8),
                _buildPhotoPreview(),
                const SizedBox(height: 12),
                _row2(
                  _field(
                    _quantityController,
                    'Menge',
                    keyboardType: TextInputType.number,
                  ),
                  _field(
                    _discountController,
                    'Rabatt in %',
                    focusNode: _discountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(height: 12),
                _row2(
                  _field(
                    _unitPriceController,
                    widget.isDealerCustomer ? 'Einzelpreis netto (Reseller)' : 'Einzelpreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _field(
                    _totalPriceController,
                    'Gesamtpreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: true,
                  ),
                ),
                _buildDiscountAmountHint(),
                const SizedBox(height: 12),
                _row2(
                  _field(
                    _itemWeightController,
                    'Gewicht in g',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _field(
                    _totalWeightController,
                    'Gesamtgewicht in g',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: true,
                  ),
                ),
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
          onPressed: () {
            if (_selectedItemId == null) {
              setState(() {});
              return;
            }

            final selected = widget.availableItems.firstWhere(
              (item) => item.icId == _selectedItemId,
            );

            final descriptionText = _descriptionController.text.trim();
            final existingDe = widget.initialValue?.ioDescriptionDeLong ?? '';
            final existingEn = widget.initialValue?.ioDescriptionEnLong ?? '';
            final descriptionDe = _isOrderLanguageDe ? descriptionText : existingDe;
            final descriptionEn = _isOrderLanguageDe ? existingEn : descriptionText;

            final result = ItemOrderedRow(
              ioId: widget.initialValue?.ioId,
              ioOrderId: _orderIdController.text.trim(),
              ioPos: _parseInt(_posController, fallback: widget.initialPos),
              ioQuantity: _parseInt(_quantityController, fallback: 1),
              ioItemId: _selectedItemId!,
              ioIdi: selected.icIdi,
              ioDescriptionDeLong: descriptionDe,
              ioDescriptionEnLong: descriptionEn,
              ioHts: selected.icHts.trim().isEmpty ? '-' : selected.icHts.trim(),
              ioColor: _colorController.text.trim().isEmpty ? '-' : _colorController.text.trim(),
              ioUnitPrice: _parseDecimal(_unitPriceController),
              ioDiscount: _roundToOneDecimal(_parseDiscountPercent()),
              ioTotalPrice: _parseDecimal(_totalPriceController),
              ioItemWeight: _parseDecimal(_itemWeightController),
              ioTotalWeight: _parseDecimal(_totalWeightController),
              ioPhoto: selected.icImagePath.trim().isEmpty ? '-' : selected.icImagePath.trim(),
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
