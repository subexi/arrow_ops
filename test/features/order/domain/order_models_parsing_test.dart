import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderRow.fromMap parsing', () {
    test('parses o_payment_actual from floating numeric sqlite value', () {
      final row = OrderRow.fromMap(
        const {
          'o_id': 'O-PA-1',
          'o_customer_id': 'C-1',
          'o_payment_actual': 2.0,
          'o_paypal_fee_actual': 0,
        },
      );

      expect(row.oPaymentActual, 2);
    });

    test('parses o_payment_actual from floating string value', () {
      final row = OrderRow.fromMap(
        const {
          'o_id': 'O-PA-2',
          'o_customer_id': 'C-1',
          'o_payment_actual': '2.0',
          'o_paypal_fee_actual': 0,
        },
      );

      expect(row.oPaymentActual, 2);
    });
  });
}
