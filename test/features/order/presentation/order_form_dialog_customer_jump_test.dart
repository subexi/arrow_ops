import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/presentation/widgets/order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer(String customerId) {
    return Customer(
      cId: customerId,
      cCompany: 'Match Company',
      cLastName: 'Last',
      cFirstName: 'First',
      cStreetB: 'Street',
      cHouseNumberB: '1',
      cPostalCodeB: '12345',
      cCityB: 'City',
      cStreetD: 'Street',
      cHouseNumberD: '1',
      cPostalCodeD: '12345',
      cCityD: 'City',
    );
  }

  OrderRow buildInitialOrder(String customerId) {
    return OrderRow(
      oId: '2601011000',
      oCustomerId: customerId,
      oCurrency: 'EUR',
      oLanguage: 'DE',
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

  testWidgets('klick auf Kunden-ID gibt open_customer Ergebnis zurueck', (
    tester,
  ) async {
    const customerId = 'C777';
    final customer = buildCustomer(customerId);
    final initialOrder = buildInitialOrder(customerId);
    String? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: FilledButton(
                  onPressed: () async {
                    final result = await showDialog<dynamic>(
                      context: context,
                      builder: (_) => OrderFormDialog(
                        allCustomers: [customer],
                        allCountries: const [],
                        initialValue: initialOrder,
                      ),
                    );
                    dialogResult = result?.toString();
                  },
                  child: const Text('Dialog oeffnen'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dialog oeffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Kunden-ID: C777'), findsOneWidget);

    await tester.tap(find.text('Kunden-ID: C777'));
    await tester.pumpAndSettle();

    expect(dialogResult, equals('open_customer:C777'));
  });

  testWidgets('ohne ausgewaehlten kunden wird kein kunden-id-sprung angezeigt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrderFormDialog(
              allCustomers: [buildCustomer('C001')],
              allCountries: const [],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Kunden-ID:'), findsNothing);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });
}
