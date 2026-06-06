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
  late final TextEditingController _childArticleController;
  int? _itemId;
  int? _parentId;

  @override
  void initState() {
    super.initState();
    final initialValue = widget.initialValue;
    _quantityController = TextEditingController(text: (initialValue?.ibQuantity ?? 1).toString());
    _childArticleController = TextEditingController();
    _itemId = initialValue?.ibItemId ?? widget.initialItemId;
    _parentId = initialValue?.ibParentId ?? widget.initialParentId;

    if (_itemId != null) {
      final initialItem = widget.catalogueItems.cast<ItemCatalogueRow?>().firstWhere(
            (item) => item?.icId == _itemId,
            orElse: () => null,
          );
      if (initialItem != null) {
        _childArticleController.text = _catalogueLabel(initialItem);
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _childArticleController.dispose();
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
    return '${name.isEmpty ? '-' : name} • #${item.icId}';
  }

  String _catalogueSearchText(ItemCatalogueRow item) {
    final name = item.icIdi.trim().toLowerCase();
    return '${item.icId} $name';
  }

  Future<void> _showChildArticlePicker(List<ItemCatalogueRow> selectableChildItems) async {
    if (selectableChildItems.isEmpty) {
      return;
    }

    final selected = await showDialog<ItemCatalogueRow>(
      context: context,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        var filtered = List<ItemCatalogueRow>.from(selectableChildItems);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyFilter(String query) {
              final normalized = query.trim().toLowerCase();
              setDialogState(() {
                if (normalized.isEmpty) {
                  filtered = List<ItemCatalogueRow>.from(selectableChildItems);
                } else {
                  filtered = selectableChildItems
                      .where((item) => _catalogueSearchText(item).contains(normalized))
                      .toList(growable: false);
                }
              });
            }

            return AlertDialog(
              title: const Text('Kind Artikel auswaehlen'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Suche',
                        hintText: 'ID oder Bezeichnung eingeben...',
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
                          final item = filtered[index];
                          final itemName = item.icIdi.trim().isEmpty ? '-' : item.icIdi.trim();
                          return ListTile(
                            dense: true,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    itemName,
                                    textAlign: TextAlign.left,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '#${item.icId}',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            onTap: () => Navigator.of(dialogContext).pop(item),
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

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _itemId = selected.icId;
      _childArticleController.text = _catalogueLabel(selected);
    });
  }

  String _parentArticleLabel(ItemBomRow? parentRow, Map<int, ItemCatalogueRow> catalogueById) {
    if (parentRow == null) {
      return 'Root / kein Parent';
    }

    final parentItem = catalogueById[parentRow.ibItemId];
    final name = parentItem?.icIdi.trim() ?? '';
    return name.isEmpty ? parentRow.ibItemId.toString() : '${parentRow.ibItemId} • $name';
  }

  String _parentDropdownLabel(ItemBomRow row, Map<int, ItemCatalogueRow> catalogueById) {
    final parentItem = catalogueById[row.ibItemId];
    final name = parentItem?.icIdi.trim() ?? '';
    final itemPart = name.isEmpty ? row.ibItemId.toString() : '${row.ibItemId} • $name';
    return '#${row.ibId ?? 0} -> $itemPart';
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
    final sortedParentRows = uniqueParentById.values.toList(growable: false)
      ..sort((a, b) => (a.ibId ?? 0).compareTo(b.ibId ?? 0));
    final validParentIds = uniqueParentById.keys.toSet();
    final fallbackParentId = sortedParentRows.cast<ItemBomRow?>().firstWhere(
          (row) => row?.ibParentId == null,
          orElse: () => null,
        )?.ibId ??
        (sortedParentRows.isEmpty ? null : sortedParentRows.first.ibId);
    final hasRawInvalidParentSelection = _parentId != null && !validParentIds.contains(_parentId);
    final hasInvalidParentSelection = hasRawInvalidParentSelection && fallbackParentId == null;
    final invalidParentId = hasInvalidParentSelection ? _parentId : null;
    final effectiveParentId = _parentId == null
        ? null
        : (validParentIds.contains(_parentId) ? _parentId : fallbackParentId);
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

    if (effectiveItemId == null && _itemId != null) {
      _itemId = null;
      _childArticleController.clear();
    } else if (effectiveItemId != null && _childArticleController.text.trim().isEmpty) {
      final selectedItem = catalogueById[effectiveItemId];
      if (selectedItem != null) {
        _childArticleController.text = _catalogueLabel(selectedItem);
      }
    }

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
                Autocomplete<ItemCatalogueRow>(
                  displayStringForOption: _catalogueLabel,
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return selectableChildItems;
                    }
                    return selectableChildItems.where((item) {
                      return _catalogueSearchText(item).contains(query);
                    });
                  },
                  onSelected: (selected) {
                    setState(() {
                      _itemId = selected.icId;
                      _childArticleController.text = _catalogueLabel(selected);
                    });
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    if (textEditingController.text != _childArticleController.text) {
                      textEditingController.value = textEditingController.value.copyWith(
                        text: _childArticleController.text,
                        selection: TextSelection.collapsed(offset: _childArticleController.text.length),
                      );
                    }

                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      enabled: hasSelectableChildItems,
                      decoration: InputDecoration(
                        labelText: 'Kind Artikel',
                        hintText: 'ID oder Bezeichnung eingeben...',
                        border: OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Liste oeffnen',
                          onPressed: hasSelectableChildItems
                              ? () => _showChildArticlePicker(selectableChildItems)
                              : null,
                          icon: const Icon(Icons.list_alt_outlined),
                        ),
                      ),
                      onChanged: (value) {
                        _childArticleController.text = value;
                        final query = value.trim().toLowerCase();
                        if (query.isEmpty) {
                          setState(() => _itemId = null);
                          return;
                        }

                        final matched = selectableChildItems.cast<ItemCatalogueRow?>().firstWhere(
                          (item) => _catalogueSearchText(item!).contains(query),
                              orElse: () => null,
                            );
                        setState(() => _itemId = matched?.icId);
                      },
                      validator: (_) {
                        if (!hasSelectableChildItems) {
                          return null;
                        }
                        if (_itemId == null) {
                          return 'Bitte einen Kind-Artikel auswaehlen.';
                        }
                        return null;
                      },
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final optionList = options.toList(growable: false);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260, minWidth: 320),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: optionList.length,
                            itemBuilder: (context, index) {
                              final option = optionList[index];
                              final optionName = option.icIdi.trim().isEmpty ? '-' : option.icIdi.trim();
                              return ListTile(
                                dense: true,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        optionName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '#${option.icId}',
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: effectiveParentId,
                  decoration: const InputDecoration(
                    labelText: 'Eltern Artikel',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Root / kein Parent'),
                    ),
                    ...sortedParentRows.map(
                      (row) => DropdownMenuItem<int?>(
                        value: row.ibId,
                        child: Text(
                          _parentDropdownLabel(row, catalogueById),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _parentId = value;
                    });
                  },
                ),
                if (effectiveParentId != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ausgewaehlter Parent: $parentDisplayLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
                if (hasInvalidParentSelection) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hinweis: Parent #$invalidParentId ist ungueltig und wurde auf Root gesetzt.',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  final normalizedParentId = effectiveParentId;

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