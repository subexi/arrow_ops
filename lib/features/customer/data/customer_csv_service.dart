import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import 'italian_billing_province_resolver.dart';
import '../domain/customer.dart';

class CustomerCsvService {
  static const List<String> headers = [
    'c_id',
    'c_company',
    'c_dealer',
    'c_vat',
    'c_vat_id',
    'c_last_name',
    'c_first_name',
    'c_careof_b',
    'c_street_b',
    'c_house_number_b',
    'c_postal_code_b',
    'c_city_b',
    'c_state_b',
    'c_country_b_id',
    'c_careof_d',
    'c_street_d',
    'c_house_number_d',
    'c_postal_code_d',
    'c_city_d',
    'c_state_d',
    'c_country_d_id',
    'c_mail',
    'c_phone',
    'c_web',
    'c_social_media',
    'c_lat',
    'c_lon',
    'c_note',
    'c_total_value_eur',
    'c_total_value_usd',
    'c_last_modified',
  ];

  static const Map<String, String> _headerAliases = {
    'latitude': 'c_lat',
    'lat': 'c_lat',
    'longitude': 'c_lon',
    'long': 'c_lon',
    'lon': 'c_lon',
    'lng': 'c_lon',
    'c_long': 'c_lon',
  };

  String _normalizeHeader(String header) {
    final lower = header.toLowerCase();
    return _headerAliases[lower] ?? header;
  }

  List<Customer> importCustomers(String csvContent) {
    final csvRows = csv.decode(csvContent);

    if (csvRows.isEmpty) {
      return const [];
    }

    final dynamicHeaders = csvRows.first;
    final normalizedHeaders = dynamicHeaders
        .map((header) => _normalizeHeader(header.toString().trim()))
        .toList();

    debugPrint('📥 CSV hat ${csvRows.length} Zeilen, ${normalizedHeaders.length} Spalten');

    final customers = <Customer>[];

    for (int rowIndex = 1; rowIndex < csvRows.length; rowIndex++) {
      final row = csvRows[rowIndex];
      
      if (row.isEmpty || row.every((value) => value.toString().trim().isEmpty)) {
        debugPrint('⊘ Zeile $rowIndex: leer, übersprungen');
        continue;
      }

      try {
        final data = <String, String>{};
        for (var i = 0; i < normalizedHeaders.length; i++) {
          final key = normalizedHeaders[i];
          final value = i < row.length ? row[i] : '';
          data[key] = value.toString();
        }

        data['c_state_b'] = resolveItalianBillingProvince(
          countryCode: data['c_country_b_id'],
          currentState: data['c_state_b'],
          city: data['c_city_b'],
        );
        data['c_state_b'] = resolveUSStateAdministrativeUnit(
          countryCode: data['c_country_b_id'],
          currentState: data['c_state_b'],
          city: data['c_city_b'],
        );
        data['c_state_b'] = resolveAustralianStateAdministrativeUnit(
          countryCode: data['c_country_b_id'],
          currentState: data['c_state_b'],
          city: data['c_city_b'],
        );
        data['c_city_b'] = appendItalianProvinceAbbreviationToCity(
          city: data['c_city_b'],
          administrativeUnit: data['c_state_b'],
        );
        data['c_city_b'] = appendUSStateAbbreviationToCity(
          city: data['c_city_b'],
          administrativeUnit: data['c_state_b'],
        );

        data['c_state_d'] = resolveItalianBillingProvince(
          countryCode: data['c_country_d_id'],
          currentState: data['c_state_d'],
          city: data['c_city_d'],
        );
        data['c_state_d'] = resolveUSStateAdministrativeUnit(
          countryCode: data['c_country_d_id'],
          currentState: data['c_state_d'],
          city: data['c_city_d'],
        );
        data['c_state_d'] = resolveAustralianStateAdministrativeUnit(
          countryCode: data['c_country_d_id'],
          currentState: data['c_state_d'],
          city: data['c_city_d'],
        );
        data['c_city_d'] = appendItalianProvinceAbbreviationToCity(
          city: data['c_city_d'],
          administrativeUnit: data['c_state_d'],
        );
        data['c_city_d'] = appendUSStateAbbreviationToCity(
          city: data['c_city_d'],
          administrativeUnit: data['c_state_d'],
        );

        final customer = Customer.fromCsvRow(data);
        customers.add(customer);
      } catch (e) {
        debugPrint('⚠️ Zeile $rowIndex: Fehler bei Parsing: $e');
      }
    }

    debugPrint('✅ CSV-Import: ${customers.length} gültige Kundendatensätze');
    return customers;
  }

  String exportCustomers(List<Customer> customers) {
    final rows = <List<dynamic>>[headers];

    for (final c in customers) {
      rows.add([
        c.cId,
        c.cCompany,
        c.cDealer ? 1 : 0,
        c.cVat ? 1 : 0,
        c.cVatId,
        c.cLastName,
        c.cFirstName,
        c.cCareofB,
        c.cStreetB,
        c.cHouseNumberB,
        c.cPostalCodeB,
        c.cCityB,
        c.cStateB,
        c.cCountryBId ?? '',
        c.cCareofD,
        c.cStreetD,
        c.cHouseNumberD,
        c.cPostalCodeD,
        c.cCityD,
        c.cStateD,
        c.cCountryDId ?? '',
        c.cMail,
        c.cPhone,
        c.cWeb,
        c.cSocialMedia,
        c.cLat,
        c.cLon,
        c.cNote,
        c.cTotalValueEur,
        c.cTotalValueUsd,
        c.cLastModified,
      ]);
    }

    return csv.encode(rows);
  }
}
