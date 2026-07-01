import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/domain/paypal_fee_rules.dart';
import 'package:arrow_ops/features/order/presentation/widgets/order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer({String deliveryCountryId = 'DE'}) {
    return Customer(
      cId: 'C001',
      cLastName: 'Mustermann',
      cFirstName: 'Max',
      cStreetB: 'Musterstrasse',
      cHouseNumberB: '1',
      cPostalCodeB: '12345',
      cCityB: 'Musterstadt',
      cStreetD: 'Musterstrasse',
      cHouseNumberD: '1',
      cPostalCodeD: '12345',
      cCityD: 'Musterstadt',
      cCountryDId: deliveryCountryId,
    );
  }

  OrderRow buildInitialOrder() {
    return const OrderRow(
      oId: '2601011000',
      oCustomerId: 'C001',
      oCurrency: 'EUR',
      oPayment: 1,
      oPriceBasis: 'net',
      oVatRate: 0,
      oValueGoods: 0,
      oVat: 0,
      oShipping: 0,
      oPaypalFee: 0,
      oTotalPrice: 0,
    );
  }

  String decimalText(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  Future<void> pumpDialog(WidgetTester tester, {String deliveryCountryId = 'DE'}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrderFormDialog(
              allCustomers: [buildCustomer(deliveryCountryId: deliveryCountryId)],
              allCountries: const [],
              initialValue: buildInitialOrder(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextFormField fieldByLabel(WidgetTester tester, String label) {
    final finder = find.widgetWithText(TextFormField, label);
    expect(finder, findsOneWidget);
    return tester.widget<TextFormField>(finder);
  }

  testWidgets('berechnet PayPal-Gebuehr rueckwaerts und setzt Gesamtpreis als Empfangsbetrag', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Warenwert netto'),
      '100,00',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Versandkosten'),
      '10,00',
    );
    await tester.pumpAndSettle();

    final netTarget = 110.0;
    final expectedFee = PayPalFeeRules.feeFromNetTargetEur(
      netTargetEur: netTarget,
      countryToken: 'DE',
    );
    final expectedTotal = netTarget + expectedFee;

    final paypalFeeField = fieldByLabel(tester, 'PayPal-Gebühr');
    final totalField = fieldByLabel(tester, 'Gesamtpreis');

    expect(paypalFeeField.controller?.text, decimalText(expectedFee));
    expect(totalField.controller?.text, decimalText(expectedTotal));
  });

  testWidgets('beruecksichtigt fuer CH den Rest-der-Welt-Satz in der Rueckwaertsberechnung', (
    tester,
  ) async {
    await pumpDialog(tester, deliveryCountryId: 'CH');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Warenwert netto'),
      '100,00',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Versandkosten'),
      '0,00',
    );
    await tester.pumpAndSettle();

    const netTarget = 100.0;
    final expectedFee = PayPalFeeRules.feeFromNetTargetEur(
      netTargetEur: netTarget,
      countryToken: 'CH',
    );
    final expectedTotal = netTarget + expectedFee;

    final paypalFeeField = fieldByLabel(tester, 'PayPal-Gebühr');
    final totalField = fieldByLabel(tester, 'Gesamtpreis');

    expect(paypalFeeField.controller?.text, decimalText(expectedFee));
    expect(totalField.controller?.text, decimalText(expectedTotal));
  });
}
