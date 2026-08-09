import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/presentation/order_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildItemSelectionKey', () {
    test('uses io_id when present', () {
      const item = ItemOrderedRow(
        ioId: 42,
        ioOrderId: '2512302119',
        ioPos: 1,
        ioItemId: 100,
        ioIdi: 'ART-100',
      );

      final key = buildItemSelectionKey(item);

      expect(key, 'id:42');
    });

    test('uses stable fallback key when io_id is missing', () {
      const item = ItemOrderedRow(
        ioId: null,
        ioOrderId: '2512302119',
        ioPos: 3,
        ioItemId: 777,
        ioIdi: 'SKU-777',
      );

      final key = buildItemSelectionKey(item);

      expect(key, 'fallback:2512302119|3|777|SKU-777');
    });

    test('fallback key differs for different row data', () {
      const a = ItemOrderedRow(
        ioId: null,
        ioOrderId: '2512302119',
        ioPos: 3,
        ioItemId: 777,
        ioIdi: 'SKU-777',
      );
      const b = ItemOrderedRow(
        ioId: null,
        ioOrderId: '2512302119',
        ioPos: 4,
        ioItemId: 777,
        ioIdi: 'SKU-777',
      );

      final keyA = buildItemSelectionKey(a);
      final keyB = buildItemSelectionKey(b);

      expect(keyA, isNot(equals(keyB)));
    });
  });

  group('payment display helpers', () {
    test('uses planned payment when no actual payment exists', () {
      final code = resolveEffectivePaymentCode(
        plannedPaymentCode: 1,
        actualPaymentCode: null,
      );
      final label = buildPaymentDisplayLabel(
        plannedPaymentCode: 1,
        actualPaymentCode: null,
      );

      expect(code, 1);
      expect(label, 'PayPal');
    });

    test('shows plan to actual label when payment changed', () {
      final code = resolveEffectivePaymentCode(
        plannedPaymentCode: 1,
        actualPaymentCode: 2,
      );
      final overridden = hasPaymentOverride(
        plannedPaymentCode: 1,
        actualPaymentCode: 2,
      );
      final label = buildPaymentDisplayLabel(
        plannedPaymentCode: 1,
        actualPaymentCode: 2,
      );

      expect(code, 2);
      expect(overridden, isTrue);
      expect(label, 'PayPal -> Banküberweisung');
    });

    test('detects no override when actual payment is null', () {
      final overridden = hasPaymentOverride(
        plannedPaymentCode: 1,
        actualPaymentCode: null,
      );

      expect(overridden, isFalse);
    });
  });
}
