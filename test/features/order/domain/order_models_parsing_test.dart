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

    test('parses cancellation and return flags from numeric strings', () {
      final row = OrderRow.fromMap(
        const {
          'o_id': 'O-RET-1',
          'o_customer_id': 'C-1',
          'o_canceled': '1.0',
          'o_returned': '1.0',
        },
      );

      expect(row.oCanceled, 1);
      expect(row.oReturned, 1);
    });

    test('parses io_backorder_pending for item rows', () {
      final row = ItemOrderedRow.fromMap(
        const {
          'io_order_id': 'O-1',
          'io_backorder_pending': '1.0',
          'io_backorder_eta': '2026-10-15',
          'io_backorder_completed': '0.0',
        },
      );

      expect(row.ioBackorderPending, 1);
      expect(row.ioBackorderEta, '2026-10-15');
      expect(row.ioBackorderCompleted, 0);
    });
  });
}
