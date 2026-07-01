import 'package:flutter/material.dart';

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
  late final FocusNode _purchaseDateFocusNode;

  late final Map<String, _CatalogueSelectionOption> _optionById;
  late final List<_CatalogueSelectionOption> _options;
  String _selectedOptionId = '';

  bool get _isWide => MediaQuery.of(context).size.width >= 760;

  @override
  void initState() {
    super.initState();

    final options = <_CatalogueSelectionOption>[];
    for (var i = 0; i < widget.catalogueItems.length; i++) {
      final item = widget.catalogueItems[i];
      final selectionKey = _selectionKeyForItem(item);
      final displayId = _displayIdForItem(item);
      final description = item.icDescriptionDeLong.trim();
      final label = description.isEmpty
          ? displayId
          : displayId;

      options.add(
        _CatalogueSelectionOption(
          optionId: 'item:${item.icId}:$i',
          storedToken: selectionKey,
          description: description,
          label: label,
        ),
      );
    }

    options.sort((a, b) =>
        a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    _options = options;
    _optionById = {
      for (final option in options) option.optionId: option,
    };

    final initial = widget.initialValue;
    final initialKey = (initial?.ppIdi ?? '').trim();
    String? initialOptionId;
    if (initialKey.isNotEmpty) {
      for (final option in _options) {
        if (option.storedToken == initialKey) {
          initialOptionId = option.optionId;
          break;
        }
      }
    }

    if (initialKey.isNotEmpty && initialOptionId == null) {
      final legacyDescription = initial?.ppDescriptionDeLong.trim() ?? '';
      final legacyOption = _CatalogueSelectionOption(
        optionId: 'legacy:$initialKey',
        storedToken: initialKey,
        description: legacyDescription,
        label: legacyDescription.isEmpty
          ? initialKey
          : initialKey,
      );
      _options.insert(0, legacyOption);
      _optionById[legacyOption.optionId] = legacyOption;
      initialOptionId = legacyOption.optionId;
    }

    _selectedOptionId = initialOptionId ??
        (_options.isEmpty ? '' : _options.first.optionId);

    _purchaseDateController = TextEditingController(text: initial?.ppPurchaseDate ?? '');
    _quantityController = TextEditingController(text: (initial?.ppQuantity ?? 0).toString());
    _priceNetController = TextEditingController(text: _decimalText(initial?.ppPriceNet));
    _totalPriceNetController = TextEditingController(text: _decimalText(initial?.ppTotalPriceNet));
    _descriptionController = TextEditingController(
      text: initial?.ppDescriptionDeLong ??
          _optionById[_selectedOptionId]?.description ??
          '',
    );
    _pointOfUseController = TextEditingController(text: initial?.ppPointOfUse ?? '');
    _partSourceController = TextEditingController(text: initial?.ppPartSource ?? '');
    _materialController = TextEditingController(text: initial?.ppMaterial ?? '');
    _noteController = TextEditingController(text: initial?.ppNote ?? '');
    _purchaseDateFocusNode = FocusNode();
    _purchaseDateFocusNode.addListener(() {
      if (_purchaseDateFocusNode.hasFocus) {
        return;
      }

      final normalized = _normalizeDateInput(_purchaseDateController.text);
      if (normalized == null || normalized == _purchaseDateController.text) {
        return;
      }

      _purchaseDateController.text = normalized;
    });

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
    _purchaseDateFocusNode.dispose();
    super.dispose();
  }

  static String _decimalText(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String? _normalizeDateInput(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      return null;
    }

    final normalizedSeparators = input.replaceAll('.', '-').replaceAll('/', '-');
    final parts = normalizedSeparators.split('-').where((part) => part.trim().isNotEmpty).toList();
    if (parts.length != 3) {
      return null;
    }

    int? year;
    int? month;
    int? day;

    if (parts[0].length == 4) {
      year = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
      day = int.tryParse(parts[2]);
    } else if (parts[2].length == 4) {
      day = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
      year = int.tryParse(parts[2]);
    } else {
      return null;
    }

    if (year == null || month == null || day == null) {
      return null;
    }

    if (year < 1000 || year > 9999) {
      return null;
    }

    final parsed = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (parsed == null || parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }

    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
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

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
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
      ppIdi: _optionById[_selectedOptionId]?.storedToken ?? '',
      ppPurchaseDate: _text(_purchaseDateController),
      ppQuantity: _parseInt(_quantityController),
      ppPriceNet: _parseDouble(_priceNetController),
      ppTotalPriceNet: _parseDouble(_totalPriceNetController),
      ppDescriptionDeLong: _text(_descriptionController),
      ppPointOfUse: _text(_pointOfUseController),
      ppPartSource: _text(_partSourceController),
      ppMaterial: _text(_materialController),
      ppNote: _text(_noteController),
    );
    Navigator.of(context).pop(row);
  }

  Future<String?> _openArticleSelectionDialog() async {
    String query = '';
    final searchFocusNode = FocusNode();
    var requestedInitialFocus = false;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!requestedInitialFocus) {
              requestedInitialFocus = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (searchFocusNode.canRequestFocus) {
                  searchFocusNode.requestFocus();
                }
              });
            }

            final normalizedQuery = query.trim().toLowerCase();
            final filteredOptions = normalizedQuery.isEmpty
                ? _options
                : _options.where((option) {
                    return option.label.toLowerCase().contains(normalizedQuery) ||
                        option.description.toLowerCase().contains(normalizedQuery) ||
                        option.storedToken.toLowerCase().contains(normalizedQuery);
                  }).toList(growable: false);

            return AlertDialog(
              title: const Text('Artikel auswählen'),
              content: SizedBox(
                width: 560,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      focusNode: searchFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Artikel suchen',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredOptions.isEmpty
                          ? const Center(child: Text('Keine Treffer'))
                          : ListView.builder(
                              itemCount: filteredOptions.length,
                              itemBuilder: (context, index) {
                                final option = filteredOptions[index];
                                return ListTile(
                                  title: Text(option.label),
                                  selected: option.optionId == _selectedOptionId,
                                  onTap: () => Navigator.of(context).pop(option.optionId),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Schließen'),
                ),
              ],
            );
          },
        );
      },
    );

    searchFocusNode.dispose();
    return result;
  }

  Widget _buildArticleSelectorField() {
    final selectedLabel = _optionById[_selectedOptionId]?.label ?? '';

    return FormField<String>(
      validator: (_) {
        if (_selectedOptionId.trim().isEmpty) {
          return 'Bitte Bezeichnung wählen';
        }
        return null;
      },
      builder: (state) {
        return InkWell(
          key: const Key('pp_article_selector_tap'),
          onTap: () async {
            final selectedOptionId = await _openArticleSelectionDialog();
            if (selectedOptionId == null) {
              return;
            }
            setState(() {
              _selectedOptionId = selectedOptionId;
              _descriptionController.text =
                  _optionById[selectedOptionId]?.description ?? '';
            });
            state.didChange(selectedOptionId);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Bezeichnung',
              border: const OutlineInputBorder(),
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              selectedLabel.isEmpty ? 'Artikel auswählen' : selectedLabel,
            ),
          ),
        );
      },
    );
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
                _buildArticleSelectorField(),
                const SizedBox(height: 12),
                _row([
                  _field(
                    _purchaseDateController,
                    'Beschaffungsdatum',
                    keyboardType: TextInputType.datetime,
                    focusNode: _purchaseDateFocusNode,
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

  String _selectionKeyForItem(ItemCatalogueRow item) {
    final idi = item.icIdi.trim();
    if (idi.isNotEmpty) {
      return idi;
    }

    final ide = item.icIde.trim();
    if (ide.isNotEmpty) {
      return ide;
    }

    return item.icId.toString();
  }

  String _displayIdForItem(ItemCatalogueRow item) {
    final idi = item.icIdi.trim();
    if (idi.isNotEmpty) {
      return idi;
    }

    final ide = item.icIde.trim();
    if (ide.isNotEmpty) {
      return ide;
    }

    return '#${item.icId}';
  }
}

class _CatalogueSelectionOption {
  const _CatalogueSelectionOption({
    required this.optionId,
    required this.storedToken,
    required this.description,
    required this.label,
  });

  final String optionId;
  final String storedToken;
  final String description;
  final String label;
}
