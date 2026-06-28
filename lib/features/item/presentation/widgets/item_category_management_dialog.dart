import 'package:flutter/material.dart';

import '../../data/item_repository.dart';
import '../../domain/item_models.dart';

class ItemCategoryManagementDialog extends StatefulWidget {
  const ItemCategoryManagementDialog({
    super.key,
    this.repository = const ItemRepository(),
  });

  final ItemRepository repository;

  @override
  State<ItemCategoryManagementDialog> createState() => _ItemCategoryManagementDialogState();
}

class _ItemCategoryManagementDialogState extends State<ItemCategoryManagementDialog> {
  bool _loading = true;
  List<ItemCategoryRow> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final categories = await widget.repository.getItemCategories();
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = categories;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _promptCategoryName({
    required String title,
    String initialValue = '',
  }) {
    var draftName = initialValue;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Kategorie',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            draftName = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draftName.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _createCategory() async {
    final name = await _promptCategoryName(title: 'Kategorie anlegen');
    if (name == null || name.isEmpty) {
      return;
    }

    try {
      final nextId = await widget.repository.nextItemCategoryId();
      await widget.repository.saveItemCategory(
        ItemCategoryRow(icatId: nextId, name: name),
      );
      await _loadCategories();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie konnte nicht gespeichert werden: $error')),
      );
    }
  }

  Future<void> _editCategory(ItemCategoryRow category) async {
    final name = await _promptCategoryName(
      title: 'Kategorie bearbeiten',
      initialValue: category.name,
    );
    if (name == null || name.isEmpty || name == category.name) {
      return;
    }

    try {
      await widget.repository.saveItemCategory(
        category.copyWith(name: name),
      );
      await _loadCategories();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie konnte nicht aktualisiert werden: $error')),
      );
    }
  }

  Future<void> _deleteCategory(ItemCategoryRow category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kategorie loeschen?'),
        content: Text(
          'Kategorie "${category.name}" wird geloescht. Zugeordnete Artikel verlieren die Kategorie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.repository.deleteItemCategory(category.icatId);
      await _loadCategories();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie konnte nicht geloescht werden: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kategorien verwalten'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _createCategory,
                      icon: const Icon(Icons.add),
                      label: const Text('Kategorie anlegen'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _categories.isEmpty
                        ? const Center(child: Text('Noch keine Kategorien vorhanden.'))
                        : ListView.separated(
                            itemCount: _categories.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              return ListTile(
                                title: Text(category.name),
                                subtitle: Text('ID: ${category.icatId}'),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Bearbeiten',
                                      onPressed: () => _editCategory(category),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Loeschen',
                                      onPressed: () => _deleteCategory(category),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
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
          child: const Text('Schliessen'),
        ),
      ],
    );
  }
}
