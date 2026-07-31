import 'package:arrow_ops/features/customer/data/customer_repository.dart';
import 'package:arrow_ops/features/customer/domain/country_tld.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/presentation/customer_page.dart';
import 'package:arrow_ops/features/order/data/order_repository.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCustomerRepository customerRepository;
  late _FakeOrderRepository orderRepository;

  setUp(() async {
    customerRepository = _FakeCustomerRepository(
      customers: [
        const Customer(
          cId: '1000000010',
          cLastName: 'MUSTER',
          cFirstName: 'Max',
          cStreetB: 'Testweg',
          cHouseNumberB: '1',
          cPostalCodeB: '12345',
          cCityB: 'Berlin',
          cStreetD: 'Testweg',
          cHouseNumberD: '1',
          cPostalCodeD: '12345',
          cCityD: 'Berlin',
        ),
      ],
    );
    orderRepository = _FakeOrderRepository();
  });

  testWidgets(
    'aktualisiert sichtbare Netto-Summe nach Klick auf Aktualisieren',
    (tester) async {
      Future<void> pumpForUi() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerPage(
            showModuleNavigation: false,
            enableBackgroundNormalization: false,
            reloadOnVisibilityChange: false,
            initializeDatabasePath: false,
            customerRepository: customerRepository,
            orderRepository: orderRepository,
          ),
        ),
      );

      await pumpForUi();
      expect(find.text('Arrow Ops'), findsOneWidget);
      expect(find.text('Aktualisieren'), findsOneWidget);
      expect(find.text('150,00'), findsNothing);

      await orderRepository.saveOrder(
        const OrderRow(
          oId: 'O-UI-1',
          oCustomerId: '1000000010',
          oDate: '2026-06-17',
          oValueGoods: 150.0,
        ),
      );

      await tester.tap(find.text('Aktualisieren'));
      await pumpForUi();

      expect(find.text('150,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'behaelt sichtbare Netto-Summe nach Kundenupdate und Aktualisieren',
    (tester) async {
      Future<void> pumpForUi() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CustomerPage(
            showModuleNavigation: false,
            enableBackgroundNormalization: false,
            reloadOnVisibilityChange: false,
            initializeDatabasePath: false,
            customerRepository: customerRepository,
            orderRepository: orderRepository,
          ),
        ),
      );

      await pumpForUi();
      expect(find.text('Aktualisieren'), findsOneWidget);

      await orderRepository.saveOrder(
        const OrderRow(
          oId: 'O-UI-2',
          oCustomerId: '1000000010',
          oDate: '2026-06-18',
          oValueGoods: 150.0,
        ),
      );

      await tester.tap(find.text('Aktualisieren'));
      await pumpForUi();
      expect(find.text('150,00'), findsOneWidget);

      await customerRepository.update(
        const Customer(
          cId: '1000000010',
          cLastName: 'MUSTER-NEU',
          cFirstName: 'Max',
          cStreetB: 'Testweg',
          cHouseNumberB: '1',
          cPostalCodeB: '12345',
          cCityB: 'Berlin',
          cStreetD: 'Testweg',
          cHouseNumberD: '1',
          cPostalCodeD: '12345',
          cCityD: 'Berlin',
        ),
      );

      await tester.tap(find.text('Aktualisieren'));
      await pumpForUi();

      expect(find.text('150,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository({required List<Customer> customers})
      : _customers = List<Customer>.from(customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> getAll() async => List<Customer>.from(_customers);

  @override
  Future<List<CountryTld>> getAllCountries() async =>
      const [CountryTld(coTld: 'de', coName: 'Deutschland')];

  @override
  Future<void> update(Customer customer) async {
    final index = _customers.indexWhere((c) => c.cId == customer.cId);
    if (index >= 0) {
      _customers[index] = customer;
      return;
    }
    _customers.add(customer);
  }

  @override
  Future<Customer?> getById(String customerId) async {
    for (final customer in _customers) {
      if (customer.cId == customerId) {
        return customer;
      }
    }
    return null;
  }

  @override
  Future<int> normalizeItalianAdministrativeUnits() async => 0;
}

class _FakeOrderRepository extends OrderRepository {
  _FakeOrderRepository();

  final List<OrderRow> _orders = <OrderRow>[];

  @override
  Future<List<OrderRow>> getOrders() async => List<OrderRow>.from(_orders);

  @override
  Future<void> saveOrder(OrderRow order, {String? originalOrderId}) async {
    final lookupId = (originalOrderId != null && originalOrderId.trim().isNotEmpty)
        ? originalOrderId.trim()
        : order.oId;
    final index = _orders.indexWhere((o) => o.oId == lookupId);
    if (index >= 0) {
      _orders[index] = order;
      return;
    }
    _orders.add(order);
  }
}
