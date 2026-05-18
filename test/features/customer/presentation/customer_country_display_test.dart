import 'package:arrow_ops/features/customer/domain/customer.dart';
import 'package:arrow_ops/features/customer/presentation/customer_country_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Customer buildCustomer({String? billingCountry, String? deliveryCountry}) {
    return Customer(
      cId: '1',
      cLastName: 'Doe',
      cFirstName: 'Jane',
      cStreetB: 'Main St',
      cHouseNumberB: '1',
      cPostalCodeB: '12345',
      cCityB: 'Berlin',
      cStreetD: 'Second St',
      cHouseNumberD: '2',
      cPostalCodeD: '54321',
      cCityD: 'Munich',
      cCountryBId: billingCountry,
      cCountryDId: deliveryCountry,
    );
  }

  group('resolveDisplayCountry', () {
    test('uses billing country first when both are set', () {
      final customer = buildCustomer(billingCountry: 'de', deliveryCountry: 'us');
      final countries = <String, String>{'de': 'Deutschland', 'us': 'United States'};

      final result = resolveDisplayCountry(
        customer: customer,
        countryNameByCode: countries,
      );

      expect(result, 'Deutschland');
    });

    test('falls back to delivery country when billing country is empty', () {
      final customer = buildCustomer(billingCountry: '', deliveryCountry: 'us');
      final countries = <String, String>{'us': 'United States'};

      final result = resolveDisplayCountry(
        customer: customer,
        countryNameByCode: countries,
      );

      expect(result, 'United States');
    });

    test('returns uppercase code when country map has no entry', () {
      final customer = buildCustomer(billingCountry: 'ch');

      final result = resolveDisplayCountry(
        customer: customer,
        countryNameByCode: const {},
      );

      expect(result, 'CH');
    });

    test('returns fallback when no billing or delivery country is available', () {
      final customer = buildCustomer(billingCountry: '-', deliveryCountry: null);

      final result = resolveDisplayCountry(
        customer: customer,
        countryNameByCode: const {},
        fallbackWhenMissing: '-',
      );

      expect(result, '-');
    });
  });
}
