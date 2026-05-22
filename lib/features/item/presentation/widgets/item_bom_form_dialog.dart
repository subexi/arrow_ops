import 'package:flutter/material.dart';

import '../../../../core/ui/transient_feedback.dart';
import '../../domain/item_models.dart';

class ItemBomFormDialog extends StatefulWidget {
  const ItemBomFormDialog({
    super.key,
    required this.catalogueItems,
    required this.nextId,
    required this.availableBomItems,
    this.initialValue,
    this.initialParentId,
  });

  final List<ItemCatalogueRow> catalogueItems;
  final List<ItemBomRow> availableBomItems;
  final int nextId;
  final ItemBomRow? initialValue;
  final int? initialParentId;

  @override
  State<ItemBomFormDialog> createState() => _ItemBomFormDialogState();
}

class _ItemBomFormDialogState extends State<ItemBomFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool get _isWide => MediaQuery.of(context).size.width >= 720;

  late final TextEditingController _idController;
  late final TextEditingController _quantityController;
  int? _itemId;
  int? _parentId;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue;
    _idController = TextEditingController(text: (initialValue?.ibId ?? widget.nextId).toString());
    _quantityController = TextEditingController(text: (initialValue?.ibQuantity ?? 1).toString());
    _itemId = initialValue?.ibItemId;
    _parentId = initialValue?.ibParentId ?? widget.initialParentId;
  }

  @override
  void dispose() {
    _idController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  String? _validateId(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return 'Bitte eine ID angeben.';
    }
    if (int.tryParse(raw) == null) {
      return 'Bitte eine gueltige Zahl angeben.';
    }
    return null;
  }

  String? _validateQuantity(String? value) {
    final quantity = int.tryParse(value?.trim() ?? '');
    if (quantity == null) {
      return 'Bitte eine gueltige Menge angeben.';
    }
    if (quantity <= 0) {
      return 'Die Menge muss groesser als 0 sein.';
    }
    return null;
  }

  String _catalogueLabel(ItemCatalogueRow item) {
    final name = [item.icIdi, item.icIde, item.icIdv].where((value) => value.trim().isNotEmpty).join(' | ');
    return '#${item.icId}${name.isEmpty ? '' : ' • $name'}';
  }

  String _bomLabel(ItemBomRow item) => '#${item.ibId ?? 0} → Item ${item.ibItemId}';

  Widget _compactRow(List<Widget> children) {
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    final hasCatalogueItems = widget.catalogueItems.isNotEmpty;

    return AlertDialog(
      title: Text(isEditing ? 'BOM-Eintrag bearbeiten' : 'BOM-Eintrag anlegen'),
      content: SizedBox(
        width: _isWide ? 620 : 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactRow([
                  TextFormField(
                    controller: _idController,
                    enabled: !isEditing,
                    decoration: const InputDecoration(
                      labelText: 'ib_id',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateId,
                  ),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ib_quantity',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateQuantity,
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _itemId,
                  items: widget.catalogueItems
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.icId,
                          child: Text(_catalogueLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: hasCatalogueItems ? (value) => setState(() => _itemId = value) : null,
                  decoration: const InputDecoration(
                    labelText: 'ib_item_id',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null) {
                      return 'Bitte ein Katalog-Item auswaehlen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _parentId,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Root / kein Parent'),
                    ),
                    ...widget.availableBomItems.map(
                      (item) => DropdownMenuItem<int?>(
                        value: item.ibId,
                        child: Text(_bomLabel(item)),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _parentId = value),
                  decoration: const InputDecoration(
                    labelText: 'ib_parent_id',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!hasCatalogueItems) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Noch keine Katalogeintraege vorhanden. Zuerst einen Katalogeintrag anlegen.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ],
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
          onPressed: hasCatalogueItems
              ? () {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  if (_itemId == null) {
                    return;
                  }

                  final id = int.tryParse(_idController.text.trim()) ?? 0;
                  if (_parentId != null && _parentId == id) {
                    TransientFeedback.show(
                      context,
                      message: 'Ein Eintrag kann nicht sein eigener Parent sein.',
                    );
                    return;
                  }

                  final result = ItemBomRow(
                    ibId: id,
                    ibItemId: _itemId!,
                    ibParentId: _parentId,
                    ibQuantity: int.tryParse(_quantityController.text.trim()) ?? 1,
                  );
                  Navigator.of(context).pop(result);
                }
              : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}