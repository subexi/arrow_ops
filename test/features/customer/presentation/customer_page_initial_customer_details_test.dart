import 'package:arrow_ops/features/customer/data/customer_repository.dart';
import 'package:arrow_ops/features/customer/domain/country_tld.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/presentation/customer_page.dart';
import 'package:arrow_ops/features/order/data/order_repository.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomerRepository extends CustomerRepository {
  const _FakeCustomerRepository({
    required this.customers,
    required this.countries,
  });

  final List<Customer> customers;
  final List<CountryTld> countries;

  @override
  Future<List<Customer>> getAll() async => customers;

  @override
  Future<List<CountryTld>> getAllCountries() async => countries;

  @override
  Future<int> normalizeItalianAdministrativeUnits() async => 0;
}

class _FakeOrderRepository extends OrderRepository {
  const _FakeOrderRepository({required this.orders});

  final List<OrderRow> orders;

  @override
  Future<List<OrderRow>> getOrders() async => orders;
}

void main() {
  testWidgets(
    'oeffnet kundendetails automatisch fuer initialCustomerId',
    (tester) async {
      const customer = Customer(
        cId: '2512302119',
        cLastName: 'Guion',
        cFirstName: 'Francois',
        cCompany: 'Demo SARL',
        cStreetB: 'Rue Example',
        cHouseNumberB: '12',
        cPostalCodeB: '75001',
        cCityB: 'Paris',
        cCountryBId: 'fr',
        cStreetD: 'Rue Example',
        cHouseNumberD: '12',
        cPostalCodeD: '75001',
        cCityD: 'Paris',
        cCountryDId: 'fr',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerPage(
            initialCustomerId: '2512302119',
            openInitialCustomerDetails: true,
            showModuleNavigation: false,
            reloadOnVisibilityChange: false,
            enableBackgroundNormalization: false,
            initializeDatabasePath: false,
            customerRepository: _FakeCustomerRepository(
              customers: const [customer],
              countries: const [CountryTld(coTld: 'fr', coName: 'France')],
            ),
            orderRepository: const _FakeOrderRepository(orders: []),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('GUION, Francois'), findsOneWidget);
      expect(find.text('Rechnungsadresse'), findsOneWidget);
      expect(find.text('Lieferadresse'), findsOneWidget);
    },
  );

  testWidgets(
    'oeffnet kundendetails auch bei initialCustomerId mit whitespace und anderer schreibweise',
    (tester) async {
      const customer = Customer(
        cId: '2512302119',
        cLastName: 'Guion',
        cFirstName: 'Francois',
        cCompany: 'Demo SARL',
        cStreetB: 'Rue Example',
        cHouseNumberB: '12',
        cPostalCodeB: '75001',
        cCityB: 'Paris',
        cCountryBId: 'fr',
        cStreetD: 'Rue Example',
        cHouseNumberD: '12',
        cPostalCodeD: '75001',
        cCityD: 'Paris',
        cCountryDId: 'fr',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerPage(
            initialCustomerId: ' 2512302119 ',
            openInitialCustomerDetails: true,
            showModuleNavigation: false,
            reloadOnVisibilityChange: false,
            enableBackgroundNormalization: false,
            initializeDatabasePath: false,
            customerRepository: _FakeCustomerRepository(
              customers: const [customer],
              countries: const [CountryTld(coTld: 'fr', coName: 'France')],
            ),
            orderRepository: const _FakeOrderRepository(orders: []),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('GUION, Francois'), findsOneWidget);
      expect(find.text('Rechnungsadresse'), findsOneWidget);
      expect(find.text('Lieferadresse'), findsOneWidget);
    },
  );
}
