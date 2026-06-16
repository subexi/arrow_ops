import 'package:arrow_ops/features/order/presentation/order_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores initialOrderId for jump navigation', () {
    const page = OrderPage(initialOrderId: 'A-10023');
    expect(page.initialOrderId, 'A-10023');
  });
}
