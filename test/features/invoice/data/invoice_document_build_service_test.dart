import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_ops/features/customer/data/customer_repository.dart';
import 'package:arrow_ops/features/customer/domain/country_tld.dart';
import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/invoice/data/invoice_document_build_service.dart';
import 'package:arrow_ops/features/order/data/order_repository.dart';
import 'package:arrow_ops/features/order/domain/order_models.dart';

void main() {
  group('InvoiceDocumentBuildService country display', () {
    test('resolves country codes to full country names for EN documents', () async {
      const order = OrderRow(
        oId: '1001',
        oCustomerId: 'C1',
        oLanguage: 'EN',
        oDate: '2026-06-26',
        oDeliveryCountryId: 'us',
      );
      const customer = Customer(
        cId: 'C1',
        cFirstName: 'Anna',
        cLastName: 'Miller',
        cStreetB: 'Main Street',
        cHouseNumberB: '1',
        cPostalCodeB: '3000',
        cCityB: 'Melbourne',
        cCountryBId: 'au',
        cStreetD: 'Dock Road',
        cHouseNumberD: '7',
        cPostalCodeD: '90210',
        cCityD: 'Los Angeles',
        cCountryDId: 'us',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[
            CountryTld(coTld: 'au', coName: 'Australia'),
            CountryTld(coTld: 'us', coName: 'United States'),
          ],
        ),
      );

      final data = await service.buildFromOrder(orderId: '1001');

      expect(data.language, 'EN');
      expect(data.buyer.countryCode, 'Australia');
      expect(data.delivery.countryCode, 'United States');
    });

    test('keeps country code tokens for DE documents', () async {
      const order = OrderRow(
        oId: '1002',
        oCustomerId: 'C2',
        oLanguage: 'DE',
        oDate: '2026-06-26',
      );
      const customer = Customer(
        cId: 'C2',
        cFirstName: 'Max',
        cLastName: 'Beispiel',
        cStreetB: 'Hauptstrasse',
        cHouseNumberB: '2',
        cPostalCodeB: '70173',
        cCityB: 'Stuttgart',
        cCountryBId: 'de',
        cStreetD: 'Hauptstrasse',
        cHouseNumberD: '2',
        cPostalCodeD: '70173',
        cCityD: 'Stuttgart',
        cCountryDId: 'de',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[
            CountryTld(coTld: 'de', coName: 'Germany'),
          ],
        ),
      );

      final data = await service.buildFromOrder(orderId: '1002');

      expect(data.language, 'DE');
      expect(data.buyer.countryCode, 'DE');
      expect(data.delivery.countryCode, 'DE');
    });

    test('does not transfer order notes into invoice note by default', () async {
      const order = OrderRow(
        oId: '1003',
        oCustomerId: 'C3',
        oLanguage: 'DE',
        oDate: '2026-06-26',
        oNote: 'Nur intern: nicht in Rechnung',
      );
      const customer = Customer(
        cId: 'C3',
        cFirstName: 'Eva',
        cLastName: 'Beispiel',
        cStreetB: 'Testweg',
        cHouseNumberB: '5',
        cPostalCodeB: '10115',
        cCityB: 'Berlin',
        cCountryBId: 'de',
        cStreetD: 'Testweg',
        cHouseNumberD: '5',
        cPostalCodeD: '10115',
        cCityD: 'Berlin',
        cCountryDId: 'de',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[CountryTld(coTld: 'de', coName: 'Germany')],
        ),
      );

      final data = await service.buildFromOrder(orderId: '1003');

      expect(data.note, '-');
    });

    test('keeps explicit note override for invoice output', () async {
      const order = OrderRow(
        oId: '1004',
        oCustomerId: 'C4',
        oLanguage: 'DE',
        oDate: '2026-06-26',
        oNote: 'Interne Auftragsnotiz',
      );
      const customer = Customer(
        cId: 'C4',
        cFirstName: 'Tom',
        cLastName: 'Muster',
        cStreetB: 'Teststrasse',
        cHouseNumberB: '9',
        cPostalCodeB: '50667',
        cCityB: 'Koeln',
        cCountryBId: 'de',
        cStreetD: 'Teststrasse',
        cHouseNumberD: '9',
        cPostalCodeD: '50667',
        cCityD: 'Koeln',
        cCountryDId: 'de',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[CountryTld(coTld: 'de', coName: 'Germany')],
        ),
      );

      final data = await service.buildFromOrder(
        orderId: '1004',
        noteOverride: 'Bitte Nachbarn informieren',
      );

      expect(data.note, 'Bitte Nachbarn informieren');
    });

    test('prefers customer delivery address when no explicit order delivery is set', () async {
      const order = OrderRow(
        oId: '1005',
        oCustomerId: 'C5',
        oLanguage: 'DE',
        oDate: '2026-06-26',
        oDeliveryAddressDifferent: 0,
        oDeliveryName: 'Alte Lieferadresse',
        oDeliveryStreet: 'Altstrasse',
        oDeliveryHouseNumber: '99',
        oDeliveryPostalCode: '99999',
        oDeliveryCity: 'Altstadt',
        oDeliveryState: 'Old',
        oDeliveryCountryId: 'us',
      );
      const customer = Customer(
        cId: 'C5',
        cFirstName: 'Mia',
        cLastName: 'Muster',
        cStreetB: 'Rechnungsweg',
        cHouseNumberB: '1',
        cPostalCodeB: '10115',
        cCityB: 'Berlin',
        cCountryBId: 'de',
        cCareofD: 'Lager Nord',
        cStreetD: 'Lieferweg',
        cHouseNumberD: '7a',
        cPostalCodeD: '20095',
        cCityD: 'Hamburg',
        cStateD: 'HH',
        cCountryDId: 'de',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[CountryTld(coTld: 'de', coName: 'Germany')],
        ),
      );

      final data = await service.buildFromOrder(orderId: '1005');

      expect(data.delivery.name, 'Lager Nord');
      expect(data.delivery.street, 'Lieferweg');
      expect(data.delivery.houseNumber, '7a');
      expect(data.delivery.postalCode, '20095');
      expect(data.delivery.city, 'Hamburg');
      expect(data.delivery.state, 'HH');
      expect(data.delivery.countryCode, 'DE');
    });

    test('prefers explicit order delivery address when order marks different delivery', () async {
      const order = OrderRow(
        oId: '1006',
        oCustomerId: 'C6',
        oLanguage: 'DE',
        oDate: '2026-06-26',
        oDeliveryAddressDifferent: 1,
        oDeliveryName: 'Messe Stuttgart',
        oDeliveryStreet: 'Messepiazza',
        oDeliveryHouseNumber: '1',
        oDeliveryPostalCode: '70629',
        oDeliveryCity: 'Stuttgart',
        oDeliveryState: 'BW',
        oDeliveryCountryId: 'de',
      );
      const customer = Customer(
        cId: 'C6',
        cFirstName: 'Lena',
        cLastName: 'Beispiel',
        cStreetB: 'Rechnungsallee',
        cHouseNumberB: '10',
        cPostalCodeB: '50667',
        cCityB: 'Koeln',
        cCountryBId: 'de',
        cCareofD: 'Kundenlager',
        cStreetD: 'Lieferstrasse',
        cHouseNumberD: '5',
        cPostalCodeD: '80331',
        cCityD: 'Muenchen',
        cStateD: 'BY',
        cCountryDId: 'de',
      );

      final service = InvoiceDocumentBuildService(
        orderRepository: _FakeOrderRepository(order: order),
        customerRepository: _FakeCustomerRepository(
          customer: customer,
          countries: const <CountryTld>[CountryTld(coTld: 'de', coName: 'Germany')],
        ),
      );

      final data = await service.buildFromOrder(orderId: '1006');

      expect(data.delivery.name, 'Messe Stuttgart');
      expect(data.delivery.street, 'Messepiazza');
      expect(data.delivery.houseNumber, '1');
      expect(data.delivery.postalCode, '70629');
      expect(data.delivery.city, 'Stuttgart');
      expect(data.delivery.state, 'BW');
      expect(data.delivery.countryCode, 'DE');
    });
  });
}

class _FakeOrderRepository extends OrderRepository {
  const _FakeOrderRepository({required this.order});

  final OrderRow order;

  @override
  Future<OrderRow?> getOrderById(String orderId) async {
    if (orderId != order.oId) {
      return null;
    }
    return order;
  }

  @override
  Future<List<ItemOrderedRow>> getItemsForOrder(String orderId) async {
    if (orderId != order.oId) {
      return const <ItemOrderedRow>[];
    }
    return const <ItemOrderedRow>[];
  }
}

class _FakeCustomerRepository extends CustomerRepository {
  const _FakeCustomerRepository({
    required this.customer,
    required this.countries,
  });

  final Customer customer;
  final List<CountryTld> countries;

  @override
  Future<Customer?> getById(String customerId) async {
    if (customerId != customer.cId) {
      return null;
    }
    return customer;
  }

  @override
  Future<List<CountryTld>> getAllCountries() async {
    return countries;
  }
}