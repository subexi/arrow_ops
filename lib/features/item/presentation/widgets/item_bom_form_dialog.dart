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
    this.initialItemId,
  });

  final List<ItemCatalogueRow> catalogueItems;
  final List<ItemBomRow> availableBomItems;
  final int nextId;
  final ItemBomRow? initialValue;
  final int? initialParentId;
  final int? initialItemId;

  @override
  State<ItemBomFormDialog> createState() => _ItemBomFormDialogState();
}

class _ItemBomFormDialogState extends State<ItemBomFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool get _isWide => MediaQuery.of(context).size.width >= 720;

  late final TextEditingController _quantityController;
  int? _itemId;
  int? _parentId;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue;
    _quantityController = TextEditingController(text: (initialValue?.ibQuantity ?? 1).toString());
    _itemId = initialValue?.ibItemId ?? widget.initialItemId;
    _parentId = initialValue?.ibParentId ?? widget.initialParentId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
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
    final name = item.icIdi.trim();
    return '#${item.icId}${name.isEmpty ? '' : ' • $name'}';
  }

  String _parentArticleLabel(ItemBomRow? parentRow, Map<int, ItemCatalogueRow> catalogueById) {
    if (parentRow == null) {
      return 'Root / kein Parent';
    }

    final parentItem = catalogueById[parentRow.ibItemId];
    final name = parentItem?.icIdi.trim() ?? '';
    return name.isEmpty ? parentRow.ibItemId.toString() : '${parentRow.ibItemId} • $name';
  }

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
    final uniqueCatalogueById = <int, ItemCatalogueRow>{};
    for (final item in widget.catalogueItems) {
      uniqueCatalogueById.putIfAbsent(item.icId, () => item);
    }
    final uniqueCatalogueItems = uniqueCatalogueById.values.toList()
      ..sort((a, b) => a.icId.compareTo(b.icId));
    final catalogueById = {
      for (final item in uniqueCatalogueItems) item.icId: item,
    };

    final hasCatalogueItems = uniqueCatalogueItems.isNotEmpty;
    final validItemIds = uniqueCatalogueById.keys.toSet();

    final currentBomId = widget.initialValue?.ibId;
    final uniqueParentById = <int, ItemBomRow>{};
    for (final item in widget.availableBomItems) {
      final id = item.ibId;
      if (id == null || id == currentBomId || !validItemIds.contains(item.ibItemId)) {
        continue;
      }
      uniqueParentById.putIfAbsent(id, () => item);
    }
    final validParentIds = uniqueParentById.keys.toSet();
    final effectiveParentId = _parentId == null
        ? null
        : (validParentIds.contains(_parentId) ? _parentId : null);
    final effectiveParentRow = effectiveParentId == null ? null : uniqueParentById[effectiveParentId];
    final parentArticleId = effectiveParentRow?.ibItemId;

    final selectableChildItems = uniqueCatalogueItems
        .where((item) => parentArticleId == null || item.icId != parentArticleId)
        .toList(growable: false);
    final selectableChildIds = selectableChildItems.map((item) => item.icId).toSet();
    final hasSelectableChildItems = selectableChildItems.isNotEmpty;
    final effectiveItemId = _itemId == null
        ? null
        : (selectableChildIds.contains(_itemId) ? _itemId : null);
    final parentDisplayLabel = _parentArticleLabel(effectiveParentRow, catalogueById);

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
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Menge',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateQuantity,
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: effectiveItemId,
                  items: selectableChildItems
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item.icId,
                          child: Text(_catalogueLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: hasSelectableChildItems ? (value) => setState(() => _itemId = value) : null,
                  decoration: const InputDecoration(
                    labelText: 'Kind Artikel',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null) {
                      return 'Bitte einen Kind-Artikel auswaehlen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: parentDisplayLabel,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Eltern Artikel',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!hasCatalogueItems || !hasSelectableChildItems) ...[
                  const SizedBox(height: 12),
                  Text(
                    !hasCatalogueItems
                        ? 'Noch keine Katalogeintraege vorhanden. Zuerst einen Katalogeintrag anlegen.'
                        : 'Keine gueltigen Kind-Artikel verfuegbar.',
                    style: const TextStyle(color: Colors.redAccent),
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
          onPressed: (hasCatalogueItems && hasSelectableChildItems)
              ? () {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  if (_itemId == null) {
                    return;
                  }

                  final id = widget.initialValue?.ibId;
                  final nextId = widget.nextId;
                  final effectiveId = id ?? nextId;
                  final normalizedParentId = _parentId == null
                      ? null
                      : (validParentIds.contains(_parentId) ? _parentId : null);

                  if (normalizedParentId != null && normalizedParentId == effectiveId) {
                    TransientFeedback.show(
                      context,
                      message: 'Ein Eintrag kann nicht sein eigener Parent sein.',
                    );
                    return;
                  }

                  final result = ItemBomRow(
                    ibId: effectiveId,
                    ibItemId: _itemId!,
                    ibParentId: normalizedParentId,
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