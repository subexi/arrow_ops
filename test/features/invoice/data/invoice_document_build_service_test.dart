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