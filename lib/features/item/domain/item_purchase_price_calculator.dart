import 'item_models.dart';

Map<int, double> calculateDerivedPurchasePrices({
  required List<ItemCatalogueRow> catalogueRows,
  required List<ItemBomRow> bomRows,
}) {
  final catalogueById = {
    for (final item in catalogueRows) item.icId: item,
  };

  final nodeById = <int, ItemBomRow>{};
  final childrenByParentId = <int, List<ItemBomRow>>{};

  for (final row in bomRows) {
    final id = row.ibId;
    if (id == null) {
      continue;
    }
    nodeById[id] = row;
    final parentId = row.ibParentId;
    if (parentId != null) {
      childrenByParentId.putIfAbsent(parentId, () => <ItemBomRow>[]).add(row);
    }
  }

  final derivedByArticleId = <int, double>{};
  final parentNodeIds = childrenByParentId.keys.toList(growable: false)..sort();

  for (final parentNodeId in parentNodeIds) {
    final parentNode = nodeById[parentNodeId];
    if (parentNode == null) {
      continue;
    }
    final children = childrenByParentId[parentNodeId] ?? const <ItemBomRow>[];
    var computedCost = 0.0;
    for (final child in children) {
      final childArticleCost = catalogueById[child.ibItemId]?.icPurchasePriceNet ?? 0;
      computedCost += childArticleCost * child.ibQuantity;
    }
    derivedByArticleId[parentNode.ibItemId] = computedCost;
  }

  return derivedByArticleId;
}

Map<int, double> calculateDerivedWeights({
  required List<ItemCatalogueRow> catalogueRows,
  required List<ItemBomRow> bomRows,
}) {
  final catalogueById = {
    for (final item in catalogueRows) item.icId: item,
  };

  final nodeById = <int, ItemBomRow>{};
  final childrenByParentId = <int, List<ItemBomRow>>{};

  for (final row in bomRows) {
    final id = row.ibId;
    if (id == null) {
      continue;
    }
    nodeById[id] = row;
    final parentId = row.ibParentId;
    if (parentId != null) {
      childrenByParentId.putIfAbsent(parentId, () => <ItemBomRow>[]).add(row);
    }
  }

  final derivedByArticleId = <int, double>{};
  final memoizedNodeWeights = <int, double>{};
  final visitingNodeIds = <int>{};
  final parentNodeIds = childrenByParentId.keys.toList(growable: false)..sort();

  double computeWeightForNode(int nodeId) {
    final memoized = memoizedNodeWeights[nodeId];
    if (memoized != null) {
      return memoized;
    }

    if (!visitingNodeIds.add(nodeId)) {
      // Cycle guard: fallback to direct article weight to avoid infinite recursion.
      final fallbackArticleId = nodeById[nodeId]?.ibItemId;
      return fallbackArticleId == null
          ? 0.0
          : (catalogueById[fallbackArticleId]?.icWeight ?? 0.0);
    }

    var computedWeight = 0.0;
    final children = childrenByParentId[nodeId] ?? const <ItemBomRow>[];
    for (final child in children) {
      final childNodeId = child.ibId;
      final childArticleWeight = (childNodeId != null &&
              childrenByParentId.containsKey(childNodeId))
          ? computeWeightForNode(childNodeId)
          : (catalogueById[child.ibItemId]?.icWeight ?? 0.0);
      computedWeight += childArticleWeight * child.ibQuantity;
    }

    visitingNodeIds.remove(nodeId);
    memoizedNodeWeights[nodeId] = computedWeight;
    return computedWeight;
  }

  for (final parentNodeId in parentNodeIds) {
    final parentNode = nodeById[parentNodeId];
    if (parentNode == null) {
      continue;
    }
    final computedWeight = computeWeightForNode(parentNodeId);
    derivedByArticleId[parentNode.ibItemId] = computedWeight;
  }

  return derivedByArticleId;
}
