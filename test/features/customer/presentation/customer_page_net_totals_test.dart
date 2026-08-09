import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_ops/features/customer/presentation/customer_page.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';

void main() {
  group('computeEffectiveOrderNetGoods', () {
    test('returns stored net value when oValueGoods is set', () {
      const order = OrderRow(
        oId: '1001',
        oCustomerId: 'C001',
        oValueGoods: 123.45,
        oTotalPrice: 200,
        oShipping: 10,
        oPaypalFee: 2,
        oVat: 30,
      );

      final net = computeEffectiveOrderNetGoods(order);

      expect(net, closeTo(123.45, 0.0001));
    });

    test('falls back to total minus shipping, paypal fee and vat', () {
      const order = OrderRow(
        oId: '1002',
        oCustomerId: 'C001',
        oValueGoods: 0,
        oTotalPrice: 238,
        oShipping: 10,
        oPaypalFee: 3,
        oVat: 38,
      );

      final net = computeEffectiveOrderNetGoods(order);

      expect(net, closeTo(187, 0.0001));
    });

    test('keeps negative fallback values unchanged', () {
      const order = OrderRow(
        oId: '1003',
        oCustomerId: 'C001',
        oValueGoods: 0,
        oTotalPrice: 5,
        oShipping: 10,
        oPaypalFee: 2,
        oVat: 1,
      );

      final net = computeEffectiveOrderNetGoods(order);

      expect(net, closeTo(-8, 0.0001));
    });

    test('uses actual paypal fee override when available', () {
      const order = OrderRow(
        oId: '1004',
        oCustomerId: 'C001',
        oValueGoods: 120,
        oTotalPrice: 238,
        oShipping: 10,
        oPaypalFee: 3,
        oPaypalFeeActual: 8,
        oVat: 38,
      );

      final net = computeEffectiveOrderNetGoods(order);

      expect(net, closeTo(182, 0.0001));
    });

    test('uses zero paypal fee for non-paypal actual payment', () {
      const order = OrderRow(
        oId: '1005',
        oCustomerId: 'C001',
        oValueGoods: 120,
        oTotalPrice: 238,
        oShipping: 10,
        oPaypalFee: 3,
        oPaymentActual: 2,
        oVat: 38,
      );

      final net = computeEffectiveOrderNetGoods(order);

      expect(net, closeTo(190, 0.0001));
    });
  });
}
