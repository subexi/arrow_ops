import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/domain/country_tld.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:arrow_ops/features/order/presentation/widgets/order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer() {
    return const Customer(
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
      cCountryDId: 'DE',
    );
  }

  OrderRow buildInitialOrder() {
    return const OrderRow(
      oId: '2601011000',
      oCustomerId: 'C001',
      oCurrency: 'EUR',
      oFxToEur: 1,
      oLanguage: 'DE',
      oPayment: 1,
      oPriceBasis: 'net',
      oVatRate: 0,
      oValueGoods: 100,
      oVat: 0,
      oShipping: 0,
      oPaypalFee: 3,
      oTotalPrice: 103,
    );
  }

  Finder actualPaymentDropdownFinder() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<int?> &&
          widget.decoration.labelText == 'Tatsächliche Zahlart (optional)',
    );
  }

  testWidgets(
    'speichert und lädt Tatsächliche Zahlart Banküberweisung im Dialog-Roundtrip',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _OrderFormRoundtripHost(
            allCustomers: [buildCustomer()],
            allCountries: const [],
            initialOrder: buildInitialOrder(),
          ),
        ),
      );

      await tester.tap(find.text('Dialog öffnen'));
      await tester.pumpAndSettle();

      final actualDropdown = actualPaymentDropdownFinder();
      expect(actualDropdown, findsOneWidget);

      await tester.ensureVisible(actualDropdown);
      await tester.pumpAndSettle();
      await tester.tap(actualDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banküberweisung').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('savedActual:2'), findsOneWidget);

      await tester.tap(find.text('Dialog erneut öffnen'));
      await tester.pumpAndSettle();

      final reopenedDropdown = tester.widget<DropdownButtonFormField<int?>>(
        actualPaymentDropdownFinder(),
      );
      expect(reopenedDropdown.initialValue, 2);
    },
  );

  testWidgets(
    'speichert und lädt PayPal-Gebühr und tatsächliche PayPal-Gebühr',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _OrderFormRoundtripHost(
            allCustomers: [buildCustomer()],
            allCountries: const [],
            initialOrder: buildInitialOrder(),
          ),
        ),
      );

      await tester.tap(find.text('Dialog öffnen'));
      await tester.pumpAndSettle();

      final plannedFeeField = find.widgetWithText(TextFormField, 'PayPal-Gebühr');
      final actualFeeField = find.widgetWithText(
        TextFormField,
        'Tatsächliche PayPal-Gebühr (optional)',
      );
      expect(plannedFeeField, findsOneWidget);
      expect(actualFeeField, findsOneWidget);

      await tester.ensureVisible(plannedFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(plannedFeeField, '4,20');

      await tester.ensureVisible(actualFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(actualFeeField, '1,80');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('savedFee:4.2'), findsOneWidget);
      expect(find.text('savedActualFee:1.8'), findsOneWidget);

      await tester.tap(find.text('Dialog erneut öffnen'));
      await tester.pumpAndSettle();

      final reopenedPlannedFeeField = tester.widget<TextFormField>(plannedFeeField);
      final reopenedActualFeeField = tester.widget<TextFormField>(actualFeeField);
      expect(reopenedPlannedFeeField.controller?.text, '4,20');
      expect(reopenedActualFeeField.controller?.text, '1,80');
    },
  );

  testWidgets(
    'akzeptiert deutsches Zahlformat fuer beide Gebuehren (1.234,56)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _OrderFormRoundtripHost(
            allCustomers: [buildCustomer()],
            allCountries: const [],
            initialOrder: buildInitialOrder(),
          ),
        ),
      );

      await tester.tap(find.text('Dialog öffnen'));
      await tester.pumpAndSettle();

      final plannedFeeField = find.widgetWithText(TextFormField, 'PayPal-Gebühr');
      final actualFeeField = find.widgetWithText(
        TextFormField,
        'Tatsächliche PayPal-Gebühr (optional)',
      );

      await tester.ensureVisible(plannedFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(plannedFeeField, '1.234,56');

      await tester.ensureVisible(actualFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(actualFeeField, '2.345,67');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('savedFee:1234.56'), findsOneWidget);
      expect(find.text('savedActualFee:2345.67'), findsOneWidget);

      await tester.tap(find.text('Dialog erneut öffnen'));
      await tester.pumpAndSettle();

      final reopenedPlannedFeeField = tester.widget<TextFormField>(plannedFeeField);
      final reopenedActualFeeField = tester.widget<TextFormField>(actualFeeField);
      expect(reopenedPlannedFeeField.controller?.text, '1234,56');
      expect(reopenedActualFeeField.controller?.text, '2345,67');
    },
  );

  testWidgets(
    'akzeptiert englisches Zahlformat fuer beide Gebuehren (1,234.56)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _OrderFormRoundtripHost(
            allCustomers: [buildCustomer()],
            allCountries: const [],
            initialOrder: buildInitialOrder(),
          ),
        ),
      );

      await tester.tap(find.text('Dialog öffnen'));
      await tester.pumpAndSettle();

      final plannedFeeField = find.widgetWithText(TextFormField, 'PayPal-Gebühr');
      final actualFeeField = find.widgetWithText(
        TextFormField,
        'Tatsächliche PayPal-Gebühr (optional)',
      );

      await tester.ensureVisible(plannedFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(plannedFeeField, '1,234.56');

      await tester.ensureVisible(actualFeeField);
      await tester.pumpAndSettle();
      await tester.enterText(actualFeeField, '2,345.67');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.text('savedFee:1234.56'), findsOneWidget);
      expect(find.text('savedActualFee:2345.67'), findsOneWidget);

      await tester.tap(find.text('Dialog erneut öffnen'));
      await tester.pumpAndSettle();

      final reopenedPlannedFeeField = tester.widget<TextFormField>(plannedFeeField);
      final reopenedActualFeeField = tester.widget<TextFormField>(actualFeeField);
      expect(reopenedPlannedFeeField.controller?.text, '1234,56');
      expect(reopenedActualFeeField.controller?.text, '2345,67');
    },
  );
}

class _OrderFormRoundtripHost extends StatefulWidget {
  const _OrderFormRoundtripHost({
    required this.allCustomers,
    required this.allCountries,
    required this.initialOrder,
  });

  final List<Customer> allCustomers;
  final List<CountryTld> allCountries;
  final OrderRow initialOrder;

  @override
  State<_OrderFormRoundtripHost> createState() => _OrderFormRoundtripHostState();
}

class _OrderFormRoundtripHostState extends State<_OrderFormRoundtripHost> {
  OrderRow? _savedOrder;

  Future<void> _openDialog() async {
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderFormDialog(
        allCustomers: widget.allCustomers,
        allCountries: widget.allCountries,
        initialValue: _savedOrder ?? widget.initialOrder,
      ),
    );

    if (result is OrderRow) {
      setState(() {
        _savedOrder = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: _openDialog,
              child: const Text('Dialog öffnen'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _savedOrder == null ? null : _openDialog,
              child: const Text('Dialog erneut öffnen'),
            ),
            const SizedBox(height: 8),
            Text('savedActual:${_savedOrder?.oPaymentActual ?? -1}'),
            Text('savedFee:${_savedOrder?.oPaypalFee ?? -1}'),
            Text('savedActualFee:${_savedOrder?.oPaypalFeeActual ?? -1}'),
          ],
        ),
      ),
    );
  }
}
