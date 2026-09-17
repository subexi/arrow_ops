import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/presentation/order_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recalculateOrderHeaderTotals keeps net value for net price basis', () {
    const order = OrderRow(
      oId: '2609070316',
      oCustomerId: 'C1',
      oPriceBasis: 'net',
      oVatRate: 19,
      oShipping: 0,
      oPaypalFee: 0,
      oPayment: 0,
      oPutt: 0,
    );

    const customer = Customer(
      cId: 'C1',
      cLastName: 'Mustermann',
      cFirstName: 'Max',
      cStreetB: 'Musterweg',
      cHouseNumberB: '1',
      cPostalCodeB: '12345',
      cCityB: 'Berlin',
      cStreetD: 'Musterweg',
      cHouseNumberD: '1',
      cPostalCodeD: '12345',
      cCityD: 'Berlin',
      cVat: false,
    );

    const items = [
      ItemOrderedRow(
        ioOrderId: '2609070316',
        ioTotalPrice: 98.88,
        ioTotalWeight: 100,
      ),
    ];

    final updated = recalculateOrderHeaderTotals(
      order: order,
      items: items,
      customer: customer,
      cashPaymentCode: 4,
    );

    expect(updated.oValueGoods, closeTo(98.88, 0.0001));
    expect(updated.oVatRate, closeTo(19.0, 0.0001));
    expect(updated.oVat, closeTo(18.7872, 0.0001));
    expect(updated.oTotalPrice, closeTo(117.6672, 0.0001));
  });

  test('recalculateOrderHeaderTotals keeps cash putt rule', () {
    const order = OrderRow(
      oId: 'CASH-1',
      oCustomerId: 'C1',
      oPriceBasis: 'gross',
      oVatRate: 19,
      oShipping: 2,
      oPaypalFee: 3,
      oPayment: 4,
      oPutt: 1,
    );

    const items = [
      ItemOrderedRow(
        ioOrderId: 'CASH-1',
        ioTotalPrice: 50.0,
        ioTotalWeight: 80,
      ),
    ];

    final updated = recalculateOrderHeaderTotals(
      order: order,
      items: items,
      customer: null,
      cashPaymentCode: 4,
    );

    expect(updated.oVatRate, closeTo(0.0, 0.0001));
    expect(updated.oVat, closeTo(0.0, 0.0001));
    expect(updated.oValueGoods, closeTo(50.0, 0.0001));
    expect(updated.oTotalPrice, closeTo(50.0, 0.0001));
  });

  test('recalculateOrderHeaderTotals applies eu reverse-charge for reseller', () {
    const order = OrderRow(
      oId: '2609031236',
      oCustomerId: 'C2',
      oPriceBasis: 'net',
      oVatRate: 19,
      oShipping: 20,
      oPaypalFee: 0,
      oPayment: 1,
      oPutt: 0,
      oDealer: 1,
    );

    const customer = Customer(
      cId: 'C2',
      cLastName: 'Roeck',
      cFirstName: 'Samuel',
      cStreetB: 'Via Roma',
      cHouseNumberB: '12',
      cPostalCodeB: '39100',
      cCityB: 'Bolzano',
      cStreetD: 'Via Roma',
      cHouseNumberD: '12',
      cPostalCodeD: '39100',
      cCityD: 'Bolzano',
      cCountryBId: 'it',
      cCountryDId: 'it',
      cDealer: true,
      cVat: false,
      cVatId: 'IT02953430218',
    );

    const items = [
      ItemOrderedRow(
        ioOrderId: '2609031236',
        ioTotalPrice: 65.92,
        ioTotalWeight: 696,
      ),
    ];

    final updated = recalculateOrderHeaderTotals(
      order: order,
      items: items,
      customer: customer,
      cashPaymentCode: 4,
    );

    expect(updated.oValueGoods, closeTo(65.92, 0.0001));
    expect(updated.oVatRate, closeTo(0.0, 0.0001));
    expect(updated.oVat, closeTo(0.0, 0.0001));
    expect(updated.oTotalPrice, closeTo(85.92, 0.0001));
  });
}
