import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/data/invoice_calculation_service.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';

void main() {
  group('InvoiceCalculationService', () {
    const service = InvoiceCalculationService();

    test('calculates gross basis totals correctly', () {
      const order = OrderRow(
        oId: '1001',
        oCustomerId: 'C1',
        oPriceBasis: 'gross',
        oVatRate: 20,
        oShipping: 5,
        oPaypalFee: 1,
      );

      const customer = Customer(
        cId: 'C1',
        cLastName: 'Doe',
        cFirstName: 'Jane',
        cStreetB: 'Main',
        cHouseNumberB: '1',
        cPostalCodeB: '12345',
        cCityB: 'Town',
        cStreetD: 'Main',
        cHouseNumberD: '1',
        cPostalCodeD: '12345',
        cCityD: 'Town',
        cVat: false,
      );

      const items = [
        ItemOrderedRow(ioOrderId: '1001', ioTotalPrice: 120, ioTotalWeight: 50),
        ItemOrderedRow(ioOrderId: '1001', ioTotalPrice: 60, ioTotalWeight: 30),
      ];

      final totals = service.calculateTotals(order: order, items: items, customer: customer);

      expect(totals.itemsGross, closeTo(180.0, 0.0001));
      expect(totals.itemsNet, closeTo(150.0, 0.0001));
      expect(totals.vatAmount, closeTo(30.0, 0.0001));
      expect(totals.grandTotal, closeTo(186.0, 0.0001));
      expect(totals.totalWeightInGram, closeTo(80.0, 0.0001));
    });

    test('forces no VAT for no-vat customer', () {
      const order = OrderRow(
        oId: '1002',
        oCustomerId: 'C2',
        oPriceBasis: 'gross',
        oVatRate: 19,
        oShipping: 3,
        oPaypalFee: 2,
      );

      const customer = Customer(
        cId: 'C2',
        cLastName: 'Miller',
        cFirstName: 'Sam',
        cStreetB: 'Side',
        cHouseNumberB: '2',
        cPostalCodeB: '54321',
        cCityB: 'City',
        cStreetD: 'Side',
        cHouseNumberD: '2',
        cPostalCodeD: '54321',
        cCityD: 'City',
        cVat: true,
      );

      const items = [
        ItemOrderedRow(ioOrderId: '1002', ioTotalPrice: 100, ioTotalWeight: 10),
      ];

      final totals = service.calculateTotals(order: order, items: items, customer: customer);

      expect(totals.vatRate, closeTo(0.0, 0.0001));
      expect(totals.vatAmount, closeTo(0.0, 0.0001));
      expect(totals.itemsNet, closeTo(100.0, 0.0001));
      expect(totals.itemsGross, closeTo(100.0, 0.0001));
      expect(totals.grandTotal, closeTo(105.0, 0.0001));
    });

    test('builds line descriptions from language and fallback', () {
      const items = [
        ItemOrderedRow(
          ioOrderId: '1003',
          ioPos: 1,
          ioItemId: 88,
          ioIdi: 'A-88',
          ioDescriptionDeLong: 'Deutsch',
          ioDescriptionEnLong: 'English',
          ioQuantity: 2,
          ioUnitPrice: 10,
          ioDiscount: 5,
          ioTotalPrice: 19,
          ioTotalWeight: 30,
        ),
        ItemOrderedRow(
          ioOrderId: '1003',
          ioPos: 2,
          ioItemId: 99,
          ioIdi: 'A-99',
          ioDescriptionDeLong: '',
          ioDescriptionEnLong: 'Fallback EN',
          ioQuantity: 1,
          ioUnitPrice: 7,
          ioDiscount: 0,
          ioTotalPrice: 7,
          ioTotalWeight: 20,
        ),
      ];

      final linesDe = service.buildLines(items: items, language: 'DE');
      expect(linesDe[0].description, 'Deutsch');
      expect(linesDe[1].description, 'Fallback EN');

      final linesEn = service.buildLines(items: items, language: 'EN');
      expect(linesEn[0].description, 'English');
      expect(linesEn[1].description, 'Fallback EN');
    });
  });
}
