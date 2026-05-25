import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/sync/icloud_sync_service.dart';
import '../data/item_image_storage_service.dart';
import '../data/item_repository.dart';
import '../domain/item_models.dart';
import 'widgets/item_bom_form_dialog.dart';
import 'widgets/item_catalogue_form_dialog.dart';

class ItemCataloguePage extends StatefulWidget {
  const ItemCataloguePage({super.key});

  @override
  State<ItemCataloguePage> createState() => _ItemCataloguePageState();
}

class _ItemCataloguePageState extends State<ItemCataloguePage> {
  final ItemRepository _repository = const ItemRepository();
  final ItemImageStorageService _imageStorage = const ItemImageStorageService();
  final ICloudSyncService _icloudSync = const ICloudSyncService();

  late final TextEditingController _searchController;
  late final ScrollController _catalogueVerticalController;
  late final ScrollController _catalogueHorizontalController;
  late final ScrollController _bomVerticalController;
  late final ScrollController _bomHorizontalController;

  List<ItemCatalogueRow> _catalogueItems = const [];
  List<ItemBomRow> _bomItems = const [];
  Map<int, ItemCatalogueRow> _catalogueById = const {};
  String _searchQuery = '';
  bool _loading = true;

  int? _selectedCatalogueId;
  int? _selectedBomId;
  _CatalogueFilter _catalogueFilter = _CatalogueFilter.all;
  int _catalogueSortColumnIndex = 0;
  bool _catalogueSortAscending = true;
  int _bomSortColumnIndex = 0;
  bool _bomSortAscending = true;

  static const List<String> _catalogueSortLabels = [
    'Artikel-ID',
    'Bezeichnung',
    'Bruttopreis',
    'Nettopreis',
    'Netto Haendlerpreis',
    'Netto Einkaufspreis',
    'Gewicht in g',
    'HTS Code',
    'Bestand',
  ];
  static const List<String> _bomSortLabels = ['ID', 'Artikel-ID', 'Eltern Artikel-ID', 'Menge', 'Bezeichnung'];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _catalogueVerticalController = ScrollController();
    _catalogueHorizontalController = ScrollController();
    _bomVerticalController = ScrollController();
    _bomHorizontalController = ScrollController();
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() => _searchQuery = nextQuery);
    });
    _loadData();
  }

  @override
  void dispose() {
    _catalogueVerticalController.dispose();
    _catalogueHorizontalController.dispose();
    _bomVerticalController.dispose();
    _bomHorizontalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final catalogueItems = await _repository.getCatalogueItems();
      await _repository.deleteOrphanBomItems(
        validCatalogueIds: catalogueItems.map((item) => item.icId).toSet(),
      );
      final bomItems = await _repository.getBomItems();
      await _syncManagedCatalogueImages(catalogueItems);
      if (!mounted) {
        return;
      }

      final catalogueById = {
        for (final item in catalogueItems) item.icId: item,
      };

      var nextSelectedCatalogueId = _selectedCatalogueId;
      if (nextSelectedCatalogueId == null || !catalogueById.containsKey(nextSelectedCatalogueId)) {
        nextSelectedCatalogueId = catalogueItems.isEmpty ? null : catalogueItems.first.icId;
      }

      final visibleBom = _buildVisibleBomRows(
        selectedCatalogueId: nextSelectedCatalogueId,
        allBomRows: bomItems,
        includeRoots: false,
      );

      var nextSelectedBomId = _selectedBomId;
      if (nextSelectedBomId == null || !visibleBom.any((row) => row.ibId == nextSelectedBomId)) {
        nextSelectedBomId = visibleBom.isEmpty ? null : visibleBom.first.ibId;
      }

      setState(() {
        _catalogueItems = catalogueItems;
        _bomItems = bomItems;
        _catalogueById = catalogueById;
        _selectedCatalogueId = nextSelectedCatalogueId;
        _selectedBomId = nextSelectedBomId;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncManagedCatalogueImages(List<ItemCatalogueRow> catalogueItems) async {
    final managedPaths = catalogueItems
        .map((item) => item.icImagePath.trim())
        .where((path) => path.isNotEmpty && !p.isAbsolute(path))
        .toSet();

    for (final path in managedPaths) {
      await _icloudSync.syncManagedImage(path);
    }
  }

  int _nextCatalogueId() => _catalogueItems.isEmpty
      ? 1
      : _catalogueItems.map((item) => item.icId).reduce((a, b) => a > b ? a : b) + 1;

  int _nextBomId() => _bomItems.isEmpty
      ? 1
      : _bomItems.map((item) => item.ibId ?? 0).reduce((a, b) => a > b ? a : b) + 1;

  String _formatDecimal(double value, int fractionDigits) {
    return value.toStringAsFixed(fractionDigits).replaceAll('.', ',');
  }

  double _grossPrice(double netPrice) => netPrice * 1.19;

  Widget _leftAlignedHeader(String text) {
    return SizedBox(
      width: double.infinity,
      child: Text(text, textAlign: TextAlign.left),
    );
  }

  DataCell _catalogueDetailCell(Widget child, ItemCatalogueRow item) {
    return DataCell(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _showCatalogueReadOnly(item),
        child: SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
    );
  }

  bool _matchesCatalogueQuery(ItemCatalogueRow item) {
    if (_searchQuery.isEmpty) {
      return true;
    }
    final text = [
      item.icIdi,
      item.icDescriptionDeLong,
      item.icDescriptionEnLong,
      item.icNote,
    ].join(' | ').toLowerCase();
    return text.contains(_searchQuery);
  }

  bool _matchesCatalogueFilter(ItemCatalogueRow item) {
    switch (_catalogueFilter) {
      case _CatalogueFilter.all:
        return true;
      case _CatalogueFilter.zbOnly:
        return item.icIc != 0;
      case _CatalogueFilter.withoutZb:
        return item.icIc == 0;
    }
  }

  List<ItemCatalogueRow> _visibleCatalogueRows() {
    final result = _catalogueItems
        .where((item) => _matchesCatalogueQuery(item) && _matchesCatalogueFilter(item))
        .toList();
    result.sort((a, b) {
      final compare = _compareCatalogueByColumn(a, b, _catalogueSortColumnIndex);
      return _catalogueSortAscending ? compare : -compare;
    });
    return result;
  }

  List<ItemBomRow> _visibleBomRows() {
    final result = List<ItemBomRow>.from(
      _buildVisibleBomRows(
        selectedCatalogueId: _selectedCatalogueId,
        allBomRows: _bomItems,
        includeRoots: false,
      ),
    ).where((row) => _catalogueById.containsKey(row.ibItemId)).toList(growable: false);
    result.sort((a, b) {
      final compare = _compareBomByColumn(a, b, _bomSortColumnIndex);
      return _bomSortAscending ? compare : -compare;
    });
    return result;
  }

  int _compareCatalogueByColumn(ItemCatalogueRow a, ItemCatalogueRow b, int columnIndex) {
    switch (columnIndex) {
      case 0:
        return a.icId.compareTo(b.icId);
      case 1:
        return a.icIdi.toLowerCase().compareTo(b.icIdi.toLowerCase());
      case 2:
        return _grossPrice(a.icPriceNet).compareTo(_grossPrice(b.icPriceNet));
      case 3:
        return a.icPriceNet.compareTo(b.icPriceNet);
      case 4:
        return a.icPriceWholesaleNet.compareTo(b.icPriceWholesaleNet);
      case 5:
        return a.icPurchasePriceNet.compareTo(b.icPurchasePriceNet);
      case 6:
        return a.icWeight.compareTo(b.icWeight);
      case 7:
        return a.icHts.toLowerCase().compareTo(b.icHts.toLowerCase());
      case 8:
        return a.icStock.compareTo(b.icStock);
      default:
        return a.icId.compareTo(b.icId);
    }
  }

  int _compareBomByColumn(ItemBomRow a, ItemBomRow b, int columnIndex) {
    switch (columnIndex) {
      case 0:
        return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
      case 1:
        return a.ibItemId.compareTo(b.ibItemId);
      case 2:
        return (a.ibParentId ?? -1).compareTo(b.ibParentId ?? -1);
      case 3:
        return a.ibQuantity.compareTo(b.ibQuantity);
      case 4:
        final aIdi = (_catalogueById[a.ibItemId]?.icIdi ?? '').toLowerCase();
        final bIdi = (_catalogueById[b.ibItemId]?.icIdi ?? '').toLowerCase();
        return aIdi.compareTo(bIdi);
      default:
        return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
    }
  }

  void _onCatalogueSort(int columnIndex, bool ascending) {
    setState(() {
      _catalogueSortColumnIndex = columnIndex;
      _catalogueSortAscending = ascending;
    });
  }

  void _onBomSort(int columnIndex, bool ascending) {
    setState(() {
      _bomSortColumnIndex = columnIndex;
      _bomSortAscending = ascending;
    });
  }

  void _resetCatalogueSort() {
    setState(() {
      _catalogueSortColumnIndex = 0;
      _catalogueSortAscending = true;
    });
  }

  void _resetBomSort() {
    setState(() {
      _bomSortColumnIndex = 0;
      _bomSortAscending = true;
    });
  }

  ItemBomRow? _selectedBomFrom(List<ItemBomRow> rows) {
    final selectedId = _selectedBomId;
    if (selectedId == null) {
      return null;
    }
    for (final row in rows) {
      if (row.ibId == selectedId) {
        return row;
      }
    }
    return null;
  }

  String _safeCatalogueSortLabel() {
    if (_catalogueSortColumnIndex < 0 || _catalogueSortColumnIndex >= _catalogueSortLabels.length) {
      return _catalogueSortLabels.first;
    }
    return _catalogueSortLabels[_catalogueSortColumnIndex];
  }

  String _safeBomSortLabel() {
    if (_bomSortColumnIndex < 0 || _bomSortColumnIndex >= _bomSortLabels.length) {
      return _bomSortLabels.first;
    }
    return _bomSortLabels[_bomSortColumnIndex];
  }

  List<ItemBomRow> _buildVisibleBomRows({
    required int? selectedCatalogueId,
    required List<ItemBomRow> allBomRows,
    required bool includeRoots,
  }) {
    if (selectedCatalogueId == null) {
      return const [];
    }

    final roots = allBomRows
      .where((row) => row.ibItemId == selectedCatalogueId && row.ibParentId == null)
        .toList(growable: false);

    if (roots.isEmpty) {
      return const [];
    }

    final byParent = <int, List<ItemBomRow>>{};
    for (final row in allBomRows) {
      final parentId = row.ibParentId;
      if (parentId == null) {
        continue;
      }
      byParent.putIfAbsent(parentId, () => <ItemBomRow>[]).add(row);
    }

    final includedIds = <int>{};
    final result = <ItemBomRow>[];
    final queue = <int>[];

    for (final root in roots) {
      final rootId = root.ibId;
      if (rootId == null) {
        if (includeRoots) {
          result.add(root);
        }
        continue;
      }
      if (includedIds.add(rootId)) {
        if (includeRoots) {
          result.add(root);
        }
        queue.add(rootId);
      }
    }

    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      final children = byParent[currentId] ?? const <ItemBomRow>[];
      for (final child in children) {
        final childId = child.ibId;
        if (childId == null) {
          continue;
        }
        if (includedIds.add(childId)) {
          result.add(child);
          queue.add(childId);
        }
      }
    }

    result.sort((a, b) {
      final parentCompare = (a.ibParentId ?? -1).compareTo(b.ibParentId ?? -1);
      if (parentCompare != 0) {
        return parentCompare;
      }
      final orderCompare = a.ibOrder.compareTo(b.ibOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return (a.ibId ?? 0).compareTo(b.ibId ?? 0);
    });

    return result;
  }

  Future<void> _showCatalogueForm({ItemCatalogueRow? initialValue}) async {
    final result = await showDialog<ItemCatalogueRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemCatalogueFormDialog(
        nextId: _nextCatalogueId(),
        initialValue: initialValue,
      ),
    );

    if (result == null) {
      return;
    }

    final normalizedResult = await _normalizeCatalogueItemImagePath(result);
    await _repository.saveCatalogueItem(normalizedResult);
    await _icloudSync.syncManagedImage(normalizedResult.icImagePath);
    await _loadData();

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedCatalogueId = normalizedResult.icId;
    });
  }

  Future<void> _showCatalogueReadOnly(ItemCatalogueRow item) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ItemCatalogueFormDialog(
        nextId: item.icId,
        initialValue: item,
        readOnly: true,
      ),
    );
  }

  Future<ItemCatalogueRow> _normalizeCatalogueItemImagePath(ItemCatalogueRow item) async {
    final rawPath = item.icImagePath.trim();
    if (rawPath.isEmpty || !p.isAbsolute(rawPath)) {
      return item;
    }

    final normalizedPath = await _imageStorage.normalizeForStorage(
      rawPath: rawPath,
      itemId: item.icId,
    );
    if (normalizedPath == rawPath) {
      return item;
    }
    return item.copyWith(icImagePath: normalizedPath);
  }

  Future<void> _deleteCatalogue(ItemCatalogueRow item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Katalogeintrag loeschen?'),
        content: Text('Eintrag #${item.icId} wird inklusive zugehoeriger BOM-Eintraege geloescht.'),
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

    await _repository.deleteCatalogueItem(item.icId);
    await _loadData();
  }

  Future<void> _showBomForm({ItemBomRow? initialValue}) async {
    final selectedCatalogueId = _selectedCatalogueId;
    if (selectedCatalogueId == null && _catalogueItems.isEmpty) {
      return;
    }

    final dialogBomItems = selectedCatalogueId == null
        ? _bomItems
        : _buildVisibleBomRows(
            selectedCatalogueId: selectedCatalogueId,
            allBomRows: _bomItems,
            includeRoots: true,
          );

    var initialParentId = initialValue?.ibParentId;
    var initialItemId = initialValue?.ibItemId ?? selectedCatalogueId;

    if (initialValue == null && selectedCatalogueId != null) {
      final existingRoot = _bomItems.where((row) => row.ibItemId == selectedCatalogueId && row.ibParentId == null).cast<ItemBomRow?>().firstWhere(
            (row) => row != null,
            orElse: () => null,
          );

      ItemBomRow? rootRow = existingRoot;
      if (rootRow == null) {
        rootRow = ItemBomRow(
          ibId: await _repository.nextBomId(),
          ibItemId: selectedCatalogueId,
          ibParentId: null,
          ibQuantity: 1,
        );
        await _repository.saveBomItem(rootRow);
        await _loadData();
        if (!mounted) {
          return;
        }
      }

      initialParentId = rootRow.ibId;
      initialItemId = null;
    }

    final result = await showDialog<ItemBomRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemBomFormDialog(
        catalogueItems: _catalogueItems,
        availableBomItems: dialogBomItems,
        nextId: _nextBomId(),
        initialValue: initialValue,
        initialParentId: initialParentId,
        initialItemId: initialItemId,
      ),
    );

    if (result == null) {
      return;
    }

    await _repository.saveBomItem(result);
    await _loadData();

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedBomId = result.ibId;
    });
  }

  Future<void> _deleteBom(ItemBomRow item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('BOM-Eintrag loeschen?'),
        content: Text('Eintrag #${item.ibId ?? 0} wird inklusive aller Nachkommen geloescht.'),
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

    final id = item.ibId;
    if (id == null) {
      return;
    }

    await _repository.deleteBomItem(id);
    await _loadData();
  }

  Widget _buildCatalogueImagePreview(ItemCatalogueRow item, {double size = 40}) {
    final storedPath = item.icImagePath.trim();
    if (storedPath.isEmpty) {
      return _emptyImagePreview(size: size);
    }

    return FutureBuilder<String?>(
      future: _imageStorage.resolveAbsolutePath(storedPath),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data?.trim();
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return _emptyImagePreview(size: size);
        }

        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return _emptyImagePreview(size: size);
        }

        return Tooltip(
          message: 'Klicken zum Vergroessern',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showCatalogueImageDialog(file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _emptyImagePreview(size: size),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCatalogueImageDialog(File file) async {
    final transformController = TransformationController();

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: 620,
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

  Widget _emptyImagePreview({double size = 40}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: size * 0.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildCatalogueSection() {
    final visibleItems = _visibleCatalogueRows();
    final selectedItem = _selectedCatalogueId == null ? null : _catalogueById[_selectedCatalogueId!];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'Artikelkatalog (${_catalogueItems.length})'
                        : 'Artikelkatalog (${visibleItems.length} von ${_catalogueItems.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _showCatalogueForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading || selectedItem == null ? null : () => _showCatalogueForm(initialValue: selectedItem),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading || selectedItem == null ? null : () => _deleteCatalogue(selectedItem),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Loeschen'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Artikel suchen',
                hintText: 'Bezeichnung, Beschreibung/Description, Notiz ...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche loeschen',
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alle Artikel'),
                  selected: _catalogueFilter == _CatalogueFilter.all,
                  onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.all),
                ),
                ChoiceChip(
                  label: const Text('ZB Komponenten'),
                  selected: _catalogueFilter == _CatalogueFilter.zbOnly,
                  onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.zbOnly),
                ),
                ChoiceChip(
                  label: const Text('ohne ZB Komponenten'),
                  selected: _catalogueFilter == _CatalogueFilter.withoutZb,
                  onSelected: (_) => setState(() => _catalogueFilter = _CatalogueFilter.withoutZb),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Sortierung: ${_safeCatalogueSortLabel()} '
                  '${_catalogueSortAscending ? 'aufsteigend' : 'absteigend'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _resetCatalogueSort,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sortierung zuruecksetzen'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: visibleItems.isEmpty
                  ? const Center(child: Text('Keine Artikel im Katalog vorhanden.'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 1180;
                        const tableMinWidth = 1150.0;

                        return DataTable2(
                                showCheckboxColumn: false,
                                sortColumnIndex: _catalogueSortColumnIndex,
                                sortAscending: _catalogueSortAscending,
                                scrollController: _catalogueVerticalController,
                                horizontalScrollController: _catalogueHorizontalController,
                                isVerticalScrollBarVisible: true,
                                isHorizontalScrollBarVisible: true,
                                columnSpacing: isCompact ? 10.0 : 16.0,
                                horizontalMargin: isCompact ? 8.0 : 12.0,
                                minWidth: tableMinWidth,
                                fixedTopRows: 1,
                                columns: [
                                  DataColumn2(
                                    size: ColumnSize.S,
                                    label: _leftAlignedHeader('Artikel-ID'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.L,
                                    label: _leftAlignedHeader('Bezeichnung'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.M,
                                    label: _leftAlignedHeader('Bruttopreis\nincl. 19%'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.S,
                                    label: _leftAlignedHeader('Nettopreis'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.M,
                                    label: _leftAlignedHeader('Netto\nHaendlerpreis'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.M,
                                    label: _leftAlignedHeader('Netto\nEinkaufspreis'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.S,
                                    label: _leftAlignedHeader('Gewicht in g'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.S,
                                    label: _leftAlignedHeader('HTS Code'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    size: ColumnSize.S,
                                    label: _leftAlignedHeader('Bestand'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                    onSort: _onCatalogueSort,
                                  ),
                                  DataColumn2(
                                    fixedWidth: 56,
                                    label: _leftAlignedHeader('Bild'),
                                    headingRowAlignment: MainAxisAlignment.start,
                                  ),
                                ],
                                rows: visibleItems
                                    .map(
                                      (item) => DataRow(
                                        selected: item.icId == _selectedCatalogueId,
                                        onSelectChanged: (selected) {
                                          if (selected != true) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedCatalogueId = item.icId;
                                            _selectedBomId = null;
                                          });
                                        },
                                        cells: [
                                          _catalogueDetailCell(Text(item.icId.toString()), item),
                                          _catalogueDetailCell(Text(item.icIdi), item),
                                          _catalogueDetailCell(Text(_formatDecimal(_grossPrice(item.icPriceNet), 2)), item),
                                          _catalogueDetailCell(Text(_formatDecimal(item.icPriceNet, 2)), item),
                                          _catalogueDetailCell(Text(_formatDecimal(item.icPriceWholesaleNet, 2)), item),
                                          _catalogueDetailCell(Text(_formatDecimal(item.icPurchasePriceNet, 2)), item),
                                          _catalogueDetailCell(Text(_formatDecimal(item.icWeight, 1)), item),
                                          _catalogueDetailCell(Text(item.icHts), item),
                                          _catalogueDetailCell(Text(item.icStock.toString()), item),
                                          _catalogueDetailCell(_buildCatalogueImagePreview(item, size: 32), item),
                                        ],
                                      ),
                                    )
                                    .toList(growable: false),
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBomSection() {
    final selectedCatalogueId = _selectedCatalogueId;
    final selectedCatalogue = selectedCatalogueId == null ? null : _catalogueById[selectedCatalogueId];
    final visibleBomRows = _visibleBomRows();
    final selectedBom = _selectedBomFrom(visibleBomRows);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedCatalogue == null
                        ? 'BOM (kein Artikel ausgewaehlt)'
                        : 'BOM zu #${selectedCatalogue.icId} • ${selectedCatalogue.icIdi} (${visibleBomRows.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading || selectedCatalogueId == null ? null : () => _showBomForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Neu'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading || selectedBom == null ? null : () => _showBomForm(initialValue: selectedBom),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Bearbeiten'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading || selectedBom == null ? null : () => _deleteBom(selectedBom),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Loeschen'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Sortierung: ${_safeBomSortLabel()} '
                  '${_bomSortAscending ? 'aufsteigend' : 'absteigend'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _resetBomSort,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sortierung zuruecksetzen'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: selectedCatalogueId == null
                  ? const Center(child: Text('Bitte zuerst oben einen Artikel auswaehlen.'))
                  : visibleBomRows.isEmpty
                      ? const Center(child: Text('Keine untergeordneten BOM-Eintraege gefunden.'))
                      : Scrollbar(
                          controller: _bomHorizontalController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _bomHorizontalController,
                            scrollDirection: Axis.horizontal,
                            child: Scrollbar(
                              controller: _bomVerticalController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _bomVerticalController,
                                child: DataTable(
                              showCheckboxColumn: false,
                              sortColumnIndex: _bomSortColumnIndex,
                              sortAscending: _bomSortAscending,
                              columns: [
                                DataColumn(label: const Text('ID'), onSort: _onBomSort),
                                DataColumn(label: const Text('Artikel-ID'), onSort: _onBomSort),
                                DataColumn(label: const Text('Eltern Artikel-ID'), onSort: _onBomSort),
                                DataColumn(label: const Text('Menge'), onSort: _onBomSort),
                                DataColumn(label: const Text('Bezeichnung'), onSort: _onBomSort),
                                const DataColumn(label: Text('Bild')),
                              ],
                              rows: visibleBomRows
                                  .map((row) {
                                    final item = _catalogueById[row.ibItemId];
                                    return DataRow(
                                      selected: row.ibId == _selectedBomId,
                                      onSelectChanged: (_) {
                                        setState(() {
                                          _selectedBomId = row.ibId;
                                        });
                                      },
                                      cells: [
                                        DataCell(Text('${row.ibId ?? 0}')),
                                        DataCell(Text(row.ibItemId.toString())),
                                        DataCell(Text(row.ibParentId?.toString() ?? '')),
                                        DataCell(Text(row.ibQuantity.toString())),
                                        DataCell(Text(item?.icIdi ?? '')),
                                        DataCell(item == null ? _emptyImagePreview() : _buildCatalogueImagePreview(item)),
                                      ],
                                    );
                                  })
                                  .toList(growable: false),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikelkatalog & BOM'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(flex: 3, child: _buildCatalogueSection()),
                Expanded(flex: 2, child: _buildBomSection()),
              ],
            ),
    );
  }
}

enum _CatalogueFilter {
  all,
  zbOnly,
  withoutZb,
}
