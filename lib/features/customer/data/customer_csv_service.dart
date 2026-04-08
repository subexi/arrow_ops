import 'package:csv/csv.dart';

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
    'c_long',
    'c_note',
    'c_total_value_eur',
    'c_total_value_usd',
    'c_last_modified',
  ];

  List<Customer> importCustomers(String csvContent) {
    final csvRows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(csvContent);

    if (csvRows.isEmpty) {
      return const [];
    }

    final dynamicHeaders = csvRows.first;
    final normalizedHeaders = dynamicHeaders
        .map((header) => header.toString().trim())
        .toList();

    final customers = <Customer>[];

    for (final row in csvRows.skip(1)) {
      if (row.isEmpty || row.every((value) => value.toString().trim().isEmpty)) {
        continue;
      }

      final data = <String, String>{};
      for (var i = 0; i < normalizedHeaders.length; i++) {
        final key = normalizedHeaders[i];
        final value = i < row.length ? row[i] : '';
        data[key] = value.toString();
      }

      customers.add(Customer.fromCsvRow(data));
    }

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
        c.cLong,
        c.cNote,
        c.cTotalValueEur,
        c.cTotalValueUsd,
        c.cLastModified,
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }
}
