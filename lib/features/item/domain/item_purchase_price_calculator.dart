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
