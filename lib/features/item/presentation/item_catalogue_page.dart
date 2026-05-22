import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/sync/icloud_sync_service.dart';
import '../../../core/ui/transient_feedback.dart';
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

class _ItemCataloguePageState extends State<ItemCataloguePage> with SingleTickerProviderStateMixin {
  final ItemRepository _repository = const ItemRepository();
  final ItemImageStorageService _imageStorage = const ItemImageStorageService();
  final ICloudSyncService _icloudSync = const ICloudSyncService();

  late final TabController _tabController;
  late final TextEditingController _searchController;
  List<ItemCatalogueRow> _catalogueItems = const [];
  List<ItemBomRow> _bomItems = const [];
  Map<int, ItemCatalogueRow> _catalogueById = const {};
  String _searchQuery = '';
  bool _loading = true;

  bool get _useImmediateDrag {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController = TextEditingController();
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
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final catalogueItems = await _repository.getCatalogueItems();
      final bomItems = await _repository.getBomItems();
      await _syncManagedCatalogueImages(catalogueItems);
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogueItems = catalogueItems;
        _bomItems = bomItems;
        _catalogueById = {
          for (final item in catalogueItems) item.icId: item,
        };
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

  int _nextCatalogueId() => _catalogueItems.isEmpty ? 1 : _catalogueItems.map((item) => item.icId).reduce((a, b) => a > b ? a : b) + 1;

  int _nextBomId() => _bomItems.isEmpty ? 1 : _bomItems.map((item) => item.ibId ?? 0).reduce((a, b) => a > b ? a : b) + 1;

  bool _matchesQuery(String value) {
    if (_searchQuery.isEmpty) {
      return true;
    }
    return value.toLowerCase().contains(_searchQuery);
  }

  String _catalogueSearchText(ItemCatalogueRow item) {
    return [
      item.icId.toString(),
      item.icIdi,
      item.icIde,
      item.icIdv,
      item.icDescriptionDeLong,
      item.icDescriptionEnLong,
      item.icColorCode,
      item.icSourceOfSupply,
      item.icHts,
      item.icNote,
    ].join(' | ');
  }

  String _bomSearchText(ItemBomRow item) {
    final catalogue = _catalogueById[item.ibItemId];
    return [
      item.ibId?.toString() ?? '',
      item.ibItemId.toString(),
      item.ibParentId?.toString() ?? '',
      item.ibQuantity.toString(),
      if (catalogue != null) _catalogueSearchText(catalogue),
    ].join(' | ');
  }

  String _catalogueBreadcrumb(ItemCatalogueRow item) {
    final parts = [item.icIdi, item.icIde, item.icIdv].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? '#${item.icId}' : parts.join(' › ');
  }

  String _bomNodeLabel(ItemBomRow item) {
    final catalogue = _catalogueById[item.ibItemId];
    final label = catalogue == null ? 'Item ${item.ibItemId}' : _catalogueLabel(catalogue);
    return '#${item.ibId ?? 0} • $label';
  }

  String _bomBreadcrumb(ItemBomRow item) {
    final lineage = <String>[];
    final seen = <int>{};
    ItemBomRow? current = item;

    while (current != null) {
      final id = current.ibId;
      if (id != null && !seen.add(id)) {
        break;
      }
      final catalogue = _catalogueById[current.ibItemId];
      lineage.add(catalogue == null ? 'Item ${current.ibItemId}' : _catalogueBreadcrumb(catalogue));
      final parentId = current.ibParentId;
      current = parentId == null ? null : _bomItems.where((candidate) => candidate.ibId == parentId).cast<ItemBomRow?>().firstWhere((candidate) => candidate != null, orElse: () => null);
    }

    return lineage.reversed.join(' › ');
  }

  Color _treeTint(BuildContext context, int depth) {
    final base = Theme.of(context).colorScheme.primary;
    final opacity = (0.08 + (depth * 0.04)).clamp(0.08, 0.22);
    return base.withValues(alpha: opacity);
  }

  Color _treeBorder(BuildContext context, int depth) {
    final base = Theme.of(context).colorScheme.primary;
    final opacity = (0.24 + (depth * 0.06)).clamp(0.24, 0.48);
    return base.withValues(alpha: opacity);
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

  Future<void> _showBomForm({ItemBomRow? initialValue, int? initialParentId}) async {
    final result = await showDialog<ItemBomRow>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemBomFormDialog(
        catalogueItems: _catalogueItems,
        availableBomItems: _bomItems,
        nextId: _nextBomId(),
        initialValue: initialValue,
        initialParentId: initialParentId,
      ),
    );

    if (result == null) {
      return;
    }

    await _repository.saveBomItem(result);
    await _loadData();
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

  String _catalogueLabel(ItemCatalogueRow item) {
    final names = [item.icIdi, item.icIde, item.icIdv].where((value) => value.trim().isNotEmpty).toList();
    return names.isEmpty ? '#${item.icId}' : '#${item.icId} • ${names.join(' | ')}';
  }

  List<_BomTreeNode> _buildTree() {
    final byParent = <int?, List<ItemBomRow>>{};
    final byId = <int, ItemBomRow>{};

    for (final item in _bomItems) {
      final id = item.ibId;
      if (id != null) {
        byId[id] = item;
      }
      byParent.putIfAbsent(item.ibParentId, () => []).add(item);
    }

    List<_BomTreeNode> buildChildren(int? parentId, Set<int> visited) {
      final children = byParent[parentId] ?? const [];
      return children.map((child) {
        final childId = child.ibId;
        if (childId != null && visited.contains(childId)) {
          return _BomTreeNode(item: child, children: const []);
        }
        final nextVisited = Set<int>.from(visited);
        if (childId != null) {
          nextVisited.add(childId);
        }
        return _BomTreeNode(
          item: child,
          children: childId == null ? const [] : buildChildren(childId, nextVisited),
        );
      }).toList();
    }

    final rootCandidates = _bomItems.where((item) {
      final parentId = item.ibParentId;
      return parentId == null || !byId.containsKey(parentId);
    }).toList();

    return rootCandidates.map((item) {
      final id = item.ibId;
      return _BomTreeNode(
        item: item,
        children: id == null ? const [] : buildChildren(id, {id}),
      );
    }).toList();
  }

  Widget _buildCatalogueTab() {
    final visibleItems = _catalogueItems.where((item) => _matchesQuery(_catalogueSearchText(item))).toList();
    final hasActiveFilter = _searchQuery.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _searchQuery.isEmpty
                      ? 'Katalog (${_catalogueItems.length})'
                      : 'Katalog (${visibleItems.length} von ${_catalogueItems.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _showCatalogueForm(),
                icon: const Icon(Icons.add),
                label: const Text('Eintrag'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Suchen',
              hintText: 'Katalog filtern...',
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
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        Expanded(
          child: visibleItems.isEmpty
              ? Center(
                  child: Text(
                    hasActiveFilter
                        ? 'Keine Katalogtreffer fuer den Suchbegriff.'
                        : 'Keine Katalogeintraege vorhanden.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visibleItems.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    return Card(
                      child: ListTile(
                        leading: _buildCatalogueImagePreview(item),
                        title: Text(_catalogueLabel(item)),
                        subtitle: Text(
                          [
                            _catalogueBreadcrumb(item),
                            if (item.icDescriptionDeLong.isNotEmpty) item.icDescriptionDeLong,
                            if (item.icDescriptionEnLong.isNotEmpty) item.icDescriptionEnLong,
                            'Stock: ${item.icStock} • Preis netto: ${item.icPriceNet}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Bearbeiten',
                              onPressed: _loading ? null : () => _showCatalogueForm(initialValue: item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Loeschen',
                              onPressed: _loading ? null : () => _deleteCatalogue(item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCatalogueImagePreview(ItemCatalogueRow item) {
    final storedPath = item.icImagePath.trim();
    if (storedPath.isEmpty) {
      return _emptyImagePreview();
    }

    return FutureBuilder<String?>(
      future: _imageStorage.resolveAbsolutePath(storedPath),
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data?.trim();
        if (resolvedPath == null || resolvedPath.isEmpty) {
          return _emptyImagePreview();
        }

        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return _emptyImagePreview();
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
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _emptyImagePreview(),
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
              Positioned(
                left: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text('Hinweis: Scroll/Geste zoomt, ziehen verschiebt, Doppelklick setzt Zoom zurueck.'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    transformController.dispose();
  }

  void _showReorderSavedMessage() {
    if (!mounted) {
      return;
    }
    TransientFeedback.show(
      context,
      message: 'Position gespeichert.',
    );
  }

  Widget _emptyImagePreview() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildTreeNode(_BomTreeNode node, {int depth = 0}) {
    final item = node.item;
    final catalogue = _catalogueById[item.ibItemId];
    final label = catalogue == null ? 'Item ${item.ibItemId}' : _catalogueLabel(catalogue);
    final hasChildren = node.children.isNotEmpty;
    final breadcrumb = _bomBreadcrumb(item);

    final tint = _treeTint(context, depth);
    final borderColor = _treeBorder(context, depth);

    final card = DragTarget<ItemBomRow>(
      onWillAcceptWithDetails: (details) {
        final draggedId = details.data.ibId;
        return draggedId != null && draggedId != item.ibId;
      },
      onAcceptWithDetails: (details) async {
        final dragged = details.data;
        final draggedId = dragged.ibId;
        if (draggedId == null || draggedId == item.ibId) {
          return;
        }

        // Drop auf einen Knoten ordnet standardmaessig als Geschwister unterhalb
        // des Zielknotens ein. Das macht Positionsaenderungen im Baum eindeutig.
        await _repository.reorderBomItem(
          itemId: draggedId,
          newParentId: item.ibParentId,
          afterItemId: item.ibId,
        );
        await _loadData();
        _showReorderSavedMessage();
      },
      builder: (context, candidateData, rejectedData) {
        final isCandidate = candidateData.isNotEmpty;
        return Container(
          margin: EdgeInsets.only(left: depth * 18.0, bottom: 10),
          decoration: BoxDecoration(
            color: isCandidate ? borderColor.withValues(alpha: 0.12) : tint,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: borderColor, width: 5)),
            boxShadow: isCandidate
                ? [
                    BoxShadow(
                      color: borderColor.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: _buildNodeDraggable(
            item: item,
            node: node,
            depth: depth,
            label: label,
            breadcrumb: breadcrumb,
            hasChildren: hasChildren,
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSiblingDropZone(node: node, depth: depth, insertBefore: true),
        card,
        _buildSiblingDropZone(node: node, depth: depth, insertBefore: false),
      ],
    );
  }

  Widget _buildNodeDraggable({
    required ItemBomRow item,
    required _BomTreeNode node,
    required int depth,
    required String label,
    required String breadcrumb,
    required bool hasChildren,
  }) {
    final tile = _buildTreeTile(
      node: node,
      depth: depth,
      label: label,
      breadcrumb: breadcrumb,
      hasChildren: hasChildren,
    );

    final feedback = Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(_bomNodeLabel(item)),
          ),
        ),
      ),
    );

    if (_useImmediateDrag) {
      return Draggable<ItemBomRow>(
        data: item,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      );
    }

    return LongPressDraggable<ItemBomRow>(
      data: item,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }

  Widget _buildSiblingDropZone({
    required _BomTreeNode node,
    required int depth,
    required bool insertBefore,
  }) {
    final item = node.item;
    final zoneText = insertBefore ? 'Vor diesen Knoten einsortieren' : 'Nach diesem Knoten einsortieren';
    final zoneIcon = insertBefore ? Icons.vertical_align_top : Icons.vertical_align_bottom;
    final zoneColor = Theme.of(context).colorScheme.primary;
    final zoneContainerColor = Theme.of(context).colorScheme.primaryContainer;

    return DragTarget<ItemBomRow>(
      onWillAcceptWithDetails: (details) {
        final draggedId = details.data.ibId;
        return draggedId != null && draggedId != item.ibId;
      },
      onAcceptWithDetails: (details) async {
        final draggedId = details.data.ibId;
        if (draggedId == null || draggedId == item.ibId) {
          return;
        }
        await _repository.reorderBomItem(
          itemId: draggedId,
          newParentId: item.ibParentId,
          beforeItemId: insertBefore ? item.ibId : null,
          afterItemId: insertBefore ? null : item.ibId,
        );
        await _loadData();
        _showReorderSavedMessage();
      },
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: EdgeInsets.only(left: depth * 18.0 + 8, top: insertBefore ? 0 : 6, bottom: insertBefore ? 6 : 0),
          constraints: BoxConstraints(minHeight: active ? 34 : 26),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: active ? 8 : 6),
          decoration: BoxDecoration(
            color: active
                ? zoneContainerColor.withValues(alpha: 0.55)
                : zoneContainerColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(
                    color: zoneColor,
                    width: 1.5,
                  )
                : Border.all(color: zoneColor.withValues(alpha: 0.22), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                zoneIcon,
                size: 16,
                color: active ? zoneColor : zoneColor.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zoneText,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active ? zoneColor : zoneColor.withValues(alpha: 0.72),
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTreeTile({
    required _BomTreeNode node,
    required int depth,
    required String label,
    required String breadcrumb,
    required bool hasChildren,
  }) {
    final item = node.item;

    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        childrenPadding: const EdgeInsets.only(left: 16, right: 12, bottom: 12),
        initiallyExpanded: depth == 0,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text('${depth + 1}', style: Theme.of(context).textTheme.labelMedium),
        ),
        title: Text('#${item.ibId ?? 0} • $label'),
        subtitle: Text('Menge: ${item.ibQuantity} • Pos: ${item.ibOrder} • $breadcrumb'),
        trailing: Wrap(
          spacing: 2,
          runSpacing: 0,
          children: [
            IconButton(
              tooltip: 'Kind anlegen',
              onPressed: _loading || item.ibId == null ? null : () => _showBomForm(initialParentId: item.ibId),
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              tooltip: 'Bearbeiten',
              onPressed: _loading ? null : () => _showBomForm(initialValue: item),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Loeschen',
              onPressed: _loading ? null : () => _deleteBom(item),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        children: hasChildren
            ? node.children.map((child) => _buildTreeNode(child, depth: depth + 1)).toList()
            : [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Keine Nachkommen'),
                  ),
                ),
              ],
      ),
    );
  }

  Widget _buildBomTab() {
    final tree = _buildTree();
    final filteredTree = _searchQuery.isEmpty ? tree : _filterTree(tree);
    final visibleCount = _searchQuery.isEmpty
      ? _bomItems.length
      : _bomItems.where((item) => _matchesQuery(_bomSearchText(item))).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _searchQuery.isEmpty ? 'Baum (${_bomItems.length})' : 'Baum ($visibleCount von ${_bomItems.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _showBomForm(),
                icon: const Icon(Icons.add),
                label: const Text('BOM-Eintrag'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Suchen',
              hintText: 'Baum filtern...',
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
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        Expanded(
          child: _bomItems.isEmpty
              ? const Center(child: Text('Keine BOM-Eintraege vorhanden.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildBomDropZone(),
                    const SizedBox(height: 12),
                    if (filteredTree.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'Keine strukturierten BOM-Eintraege gefunden.'
                                : 'Keine BOM-Treffer fuer den Suchbegriff.',
                          ),
                        ),
                      )
                    else
                      ...filteredTree.map((node) => _buildTreeNode(node)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildBomDropZone() {
    final zoneColor = Theme.of(context).colorScheme.secondary;
    final zoneContainerColor = Theme.of(context).colorScheme.secondaryContainer;

    return DragTarget<ItemBomRow>(
      onWillAcceptWithDetails: (details) => details.data.ibId != null,
      onAcceptWithDetails: (details) async {
        final draggedId = details.data.ibId;
        if (draggedId == null) {
          return;
        }
        await _repository.reorderBomItem(itemId: draggedId, newParentId: null);
        await _loadData();
        _showReorderSavedMessage();
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? zoneContainerColor.withValues(alpha: 0.7)
                : zoneContainerColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? zoneColor
                  : zoneColor.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.home_outlined, color: isActive ? zoneColor : zoneColor.withValues(alpha: 0.72)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hierhin ziehen, um einen BOM-Knoten auf Root-Ebene zu setzen',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 12),
                Icon(Icons.arrow_downward, color: zoneColor),
              ],
            ],
          ),
        );
      },
    );
  }

  List<_BomTreeNode> _filterTree(List<_BomTreeNode> nodes) {
    return nodes
        .map(_filterTreeNode)
        .whereType<_BomTreeNode>()
        .toList(growable: false);
  }

  _BomTreeNode? _filterTreeNode(_BomTreeNode node) {
    final filteredChildren = _filterTree(node.children);
    final matches = _matchesQuery(_bomSearchText(node.item));
    if (!matches && filteredChildren.isEmpty) {
      return null;
    }
    return node.copyWith(children: filteredChildren);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikelbaum'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Katalog'),
            Tab(text: 'Baum'),
          ],
        ),
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCatalogueTab(),
                _buildBomTab(),
              ],
            ),
    );
  }
}

class _BomTreeNode {
  const _BomTreeNode({
    required this.item,
    required this.children,
  });

  final ItemBomRow item;
  final List<_BomTreeNode> children;

  _BomTreeNode copyWith({
    ItemBomRow? item,
    List<_BomTreeNode>? children,
  }) {
    return _BomTreeNode(
      item: item ?? this.item,
      children: children ?? this.children,
    );
  }
}