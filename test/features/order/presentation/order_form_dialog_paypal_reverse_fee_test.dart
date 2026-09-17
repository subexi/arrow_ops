import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/domain/paypal_fee_rules.dart';
import 'package:arrow_ops/features/order/presentation/widgets/order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer({
    String deliveryCountryId = 'DE',
    String billingCountryId = 'DE',
    bool isDealer = false,
    bool isNoVatCustomer = false,
    String vatId = '-',
  }) {
    return Customer(
      cId: 'C001',
      cDealer: isDealer,
      cVat: isNoVatCustomer,
      cVatId: vatId,
      cLastName: 'Mustermann',
      cFirstName: 'Max',
      cStreetB: 'Musterstrasse',
      cHouseNumberB: '1',
      cPostalCodeB: '12345',
      cCityB: 'Musterstadt',
      cCountryBId: billingCountryId,
      cStreetD: 'Musterstrasse',
      cHouseNumberD: '1',
      cPostalCodeD: '12345',
      cCityD: 'Musterstadt',
      cCountryDId: deliveryCountryId,
    );
  }

  OrderRow buildInitialOrder({
    String currency = 'EUR',
    String language = 'DE',
    double fxToEur = 1,
  }) {
    return OrderRow(
      oId: '2601011000',
      oCustomerId: 'C001',
      oCurrency: currency,
      oFxToEur: fxToEur,
      oLanguage: language,
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

  Future<void> pumpDialog(
    WidgetTester tester, {
    String deliveryCountryId = 'DE',
    String billingCountryId = 'DE',
    String currency = 'EUR',
    String language = 'DE',
    double fxToEur = 1,
    bool isDealer = false,
    bool isNoVatCustomer = false,
    String vatId = '-',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrderFormDialog(
              allCustomers: [
                buildCustomer(
                  deliveryCountryId: deliveryCountryId,
                  billingCountryId: billingCountryId,
                  isDealer: isDealer,
                  isNoVatCustomer: isNoVatCustomer,
                  vatId: vatId,
                ),
              ],
              allCountries: const [],
              initialValue: buildInitialOrder(
                currency: currency,
                language: language,
                fxToEur: fxToEur,
              ),
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

  bool fieldIsReadOnly(WidgetTester tester, String label) {
    final formFieldFinder = find.widgetWithText(TextFormField, label);
    expect(formFieldFinder, findsOneWidget);
    final editableFinder = find.descendant(
      of: formFieldFinder,
      matching: find.byType(EditableText),
    );
    expect(editableFinder, findsOneWidget);
    return tester.widget<EditableText>(editableFinder).readOnly;
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

  testWidgets('berechnet PayPal-Gebuehr auch fuer USD mit USD→EUR-Kurs und EN Sprache', (
    tester,
  ) async {
    const fxToEur = 0.87;
    await pumpDialog(
      tester,
      deliveryCountryId: 'DE',
      currency: 'USD',
      language: 'EN',
      fxToEur: fxToEur,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Warenwert netto'),
      '100,00',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Versandkosten'),
      '10,00',
    );
    await tester.pumpAndSettle();

    const amountUsd = 110.0;
    final amountEur = amountUsd * fxToEur;
    final expectedFeeEur = PayPalFeeRules.feeFromNetTargetEur(
      netTargetEur: amountEur,
      countryToken: 'DE',
    );
    final expectedFeeUsd = expectedFeeEur / fxToEur;
    final expectedTotalUsd = amountUsd + expectedFeeUsd;

    final paypalFeeField = fieldByLabel(tester, 'PayPal-Gebühr');
    final totalField = fieldByLabel(tester, 'Gesamtpreis');

    expect(paypalFeeField.controller?.text, decimalText(expectedFeeUsd));
    expect(totalField.controller?.text, decimalText(expectedTotalUsd));
  });

  testWidgets('macht MwSt-Satz editierbar fuer Netto-Reseller mit MwSt', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      isDealer: true,
      isNoVatCustomer: false,
    );

    final vatRateField = fieldByLabel(tester, 'MwSt-Satz %');

    expect(fieldIsReadOnly(tester, 'MwSt-Satz %'), isFalse);
    expect(vatRateField.controller?.text, decimalText(19));
  });

  testWidgets('laesst MwSt-Satz gesperrt fuer Netto-Reseller ohne MwSt', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      isDealer: true,
      isNoVatCustomer: true,
    );

    final vatRateField = fieldByLabel(tester, 'MwSt-Satz %');

    expect(fieldIsReadOnly(tester, 'MwSt-Satz %'), isTrue);
    expect(vatRateField.controller?.text, decimalText(0));
  });

  testWidgets('laesst MwSt-Satz gesperrt fuer EU-Reseller mit VAT-ID ausserhalb DE', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      deliveryCountryId: 'IT',
      billingCountryId: 'IT',
      isDealer: true,
      isNoVatCustomer: false,
      vatId: 'IT02953430218',
    );

    final vatRateField = fieldByLabel(tester, 'MwSt-Satz %');

    expect(fieldIsReadOnly(tester, 'MwSt-Satz %'), isTrue);
    expect(vatRateField.controller?.text, decimalText(0));
  });
}
