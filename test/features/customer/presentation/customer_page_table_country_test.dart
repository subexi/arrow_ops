import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/presentation/customer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer({
    String? billingCountry,
    String? deliveryCountry,
  }) {
    return Customer(
      cId: 'C-1',
      cLastName: 'Muster',
      cFirstName: 'Max',
      cStreetB: 'Hauptstrasse',
      cHouseNumberB: '1',
      cPostalCodeB: '10115',
      cCityB: 'Berlin',
      cStreetD: 'Nebenstrasse',
      cHouseNumberD: '2',
      cPostalCodeD: '20095',
      cCityD: 'Hamburg',
      cCountryBId: billingCountry,
      cCountryDId: deliveryCountry,
    );
  }

  List<DataColumn> buildColumns() {
    return const [
      DataColumn(label: Text('ID')),
      DataColumn(label: Text('Nachname')),
      DataColumn(label: Text('Vorname')),
      DataColumn(label: Text('Firma')),
      DataColumn(label: Text('Stadt')),
      DataColumn(label: Text('Land')),
      DataColumn(label: Text('E-Mail')),
      DataColumn(label: Text('Maps')),
    ];
  }

  testWidgets('Land-Spalte zeigt Rechnungsland aus c_country_b_id', (tester) async {
    final customers = [
      buildCustomer(billingCountry: 'de', deliveryCountry: 'us'),
    ];

    final source = CustomerDataTableSource(
      customers: customers,
      countryNameByCode: const {
        'de': 'Deutschland',
        'us': 'United States',
      },
      loading: false,
      onOpenDetails: (_) {},
      onOpenMap: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PaginatedDataTable(
            columns: buildColumns(),
            source: source,
            rowsPerPage: 10,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Deutschland'), findsOneWidget);
    expect(find.text('United States'), findsNothing);
  });

  testWidgets('Land-Spalte faellt auf Lieferland zurueck wenn Rechnungsland leer ist', (
    tester,
  ) async {
    final customers = [
      buildCustomer(billingCountry: '', deliveryCountry: 'us'),
    ];

    final source = CustomerDataTableSource(
      customers: customers,
      countryNameByCode: const {
        'us': 'United States',
      },
      loading: false,
      onOpenDetails: (_) {},
      onOpenMap: (_) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PaginatedDataTable(
            columns: buildColumns(),
            source: source,
            rowsPerPage: 10,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('United States'), findsOneWidget);
  });
}
