import 'package:arrow_ops/features/item/domain/item_models.dart';
import 'package:arrow_ops/features/item/domain/item_purchase_price_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('berechnet Eltern-Einkaufspreis aus Summe der direkten Kind-Preise mit Menge', () {
    final catalogueRows = [
      const ItemCatalogueRow(icId: 1, icIdi: 'Parent', icPurchasePriceNet: 0),
      const ItemCatalogueRow(icId: 2, icIdi: 'Child A', icPurchasePriceNet: 4.5),
      const ItemCatalogueRow(icId: 3, icIdi: 'Child B', icPurchasePriceNet: 2.0),
    ];

    final bomRows = [
      const ItemBomRow(ibId: 10, ibItemId: 1, ibParentId: null, ibQuantity: 1),
      const ItemBomRow(ibId: 11, ibItemId: 2, ibParentId: 10, ibQuantity: 2),
      const ItemBomRow(ibId: 12, ibItemId: 3, ibParentId: 10, ibQuantity: 3),
    ];

    final result = calculateDerivedPurchasePrices(
      catalogueRows: catalogueRows,
      bomRows: bomRows,
    );

    expect(result[1], closeTo(15.0, 0.000001)); // 2*4.5 + 3*2.0
  });

  test('berechnet verschachtelte BOM bottom-up', () {
    final catalogueRows = [
      const ItemCatalogueRow(icId: 1, icIdi: 'Top', icPurchasePriceNet: 0),
      const ItemCatalogueRow(icId: 2, icIdi: 'Sub', icPurchasePriceNet: 4),
      const ItemCatalogueRow(icId: 3, icIdi: 'Leaf', icPurchasePriceNet: 7.5),
    ];

    final bomRows = [
      const ItemBomRow(ibId: 10, ibItemId: 1, ibParentId: null, ibQuantity: 1),
      const ItemBomRow(ibId: 20, ibItemId: 2, ibParentId: 10, ibQuantity: 2),
      const ItemBomRow(ibId: 30, ibItemId: 3, ibParentId: 20, ibQuantity: 3),
    ];

    final result = calculateDerivedPurchasePrices(
      catalogueRows: catalogueRows,
      bomRows: bomRows,
    );

    expect(result[2], closeTo(22.5, 0.000001)); // 3 * 7.5
    expect(result[1], closeTo(8.0, 0.000001)); // 2 * price(Sub=4)
  });
}
