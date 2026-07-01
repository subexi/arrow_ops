import 'package:arrow_ops/features/analytics/presentation/analytics_page.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summiert netto-verkaeufe aus io_total_price', () {
    final items = <ItemOrderedRow>[
      const ItemOrderedRow(ioOrderId: 'O-JUNE', ioTotalPrice: 1643.23),
      const ItemOrderedRow(ioOrderId: 'O-MAY', ioTotalPrice: 1218.63),
    ];

    expect(wareinsatzSumOrderedItemNetSales(items), closeTo(2861.86, 0.0001));
  });

  test('rechnet bei preisbasis gross positionswerte auf netto um', () {
    const item = ItemOrderedRow(ioOrderId: 'O-1', ioTotalPrice: 119.0);
    const grossOrder = OrderRow(
      oId: 'O-1',
      oCustomerId: 'C-1',
      oPriceBasis: 'gross',
      oVatRate: 19,
    );

    final net = wareinsatzOrderedItemNetSalesForOrder(
      item: item,
      order: grossOrder,
    );

    expect(net, closeTo(100.0, 0.0001));
  });

  test('behaelt bei preisbasis net positionswert unveraendert', () {
    const item = ItemOrderedRow(ioOrderId: 'O-1', ioTotalPrice: 1643.23);
    const netOrder = OrderRow(
      oId: 'O-1',
      oCustomerId: 'C-1',
      oPriceBasis: 'net',
      oVatRate: 19,
    );

    final net = wareinsatzOrderedItemNetSalesForOrder(
      item: item,
      order: netOrder,
    );

    expect(net, closeTo(1643.23, 0.0001));
  });

  test('rechnet USD net mit auftragskurs in EUR um', () {
    const item = ItemOrderedRow(ioOrderId: 'O-USD', ioTotalPrice: 100.0);
    const usdOrder = OrderRow(
      oId: 'O-USD',
      oCustomerId: 'C-1',
      oCurrency: 'USD',
      oFxToEur: 0.92,
      oPriceBasis: 'net',
      oVatRate: 19,
    );

    final netEur = wareinsatzOrderedItemNetSalesForOrder(
      item: item,
      order: usdOrder,
    );

    expect(netEur, closeTo(92.0, 0.0001));
  });

  test('rechnet USD gross erst auf netto und dann in EUR um', () {
    const item = ItemOrderedRow(ioOrderId: 'O-USD-GROSS', ioTotalPrice: 119.0);
    const usdGrossOrder = OrderRow(
      oId: 'O-USD-GROSS',
      oCustomerId: 'C-1',
      oCurrency: 'USD',
      oFxToEur: 0.9,
      oPriceBasis: 'gross',
      oVatRate: 19,
    );

    final netEur = wareinsatzOrderedItemNetSalesForOrder(
      item: item,
      order: usdGrossOrder,
    );

    expect(netEur, closeTo(90.0, 0.0001));
  });

  test('zaehlt USD positionen ohne gueltigen kurs nicht', () {
    const item = ItemOrderedRow(ioOrderId: 'O-USD-UNKNOWN', ioTotalPrice: 100.0);
    const usdWithoutFx = OrderRow(
      oId: 'O-USD-UNKNOWN',
      oCustomerId: 'C-1',
      oCurrency: 'USD',
      oFxToEur: 0,
      oPriceBasis: 'net',
    );

    final netEur = wareinsatzOrderedItemNetSalesForOrder(
      item: item,
      order: usdWithoutFx,
    );

    expect(netEur, 0);
  });

  test('ordnet monate nach versanddatum statt auftragsdatum zu', () {
    const juneByDelivery = OrderRow(
      oId: 'O-JUNE',
      oCustomerId: 'C-1',
      oDate: '2026-05-20',
      oDelivery: '2026-06-10',
    );
    const mayByDelivery = OrderRow(
      oId: 'O-MAY',
      oCustomerId: 'C-1',
      oDate: '2026-06-02',
      oDelivery: '2026-05-31',
    );

    expect(wareinsatzMatchesDeliveryMonth(juneByDelivery, '2026-06'), isTrue);
    expect(wareinsatzMatchesDeliveryMonth(mayByDelivery, '2026-06'), isFalse);
  });
}
