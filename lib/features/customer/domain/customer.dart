class Customer {
  const Customer({
    required this.cId,
    this.cCompany = '-',
    this.cDealer = false,
    this.cVat = false,
    this.cVatId = '-',
    required this.cLastName,
    required this.cFirstName,
    this.cCareofB = '-',
    required this.cStreetB,
    required this.cHouseNumberB,
    required this.cPostalCodeB,
    required this.cCityB,
    this.cStateB = '-',
    this.cCountryBId,
    this.cCareofD = '-',
    required this.cStreetD,
    required this.cHouseNumberD,
    required this.cPostalCodeD,
    required this.cCityD,
    this.cStateD = '-',
    this.cCountryDId,
    this.cMail = '-',
    this.cPhone = '-',
    this.cWeb = '-',
    this.cSocialMedia = '-',
    this.cLat = 0,
    this.cLong = 0,
    this.cNote = '-',
    this.cTotalValueEur = 0,
    this.cTotalValueUsd = 0,
    this.cLastModified = 0,
  });

  final String cId;
  final String cCompany;
  final bool cDealer;
  final bool cVat;
  final String cVatId;
  final String cLastName;
  final String cFirstName;
  final String cCareofB;
  final String cStreetB;
  final String cHouseNumberB;
  final String cPostalCodeB;
  final String cCityB;
  final String cStateB;
  final String? cCountryBId;
  final String cCareofD;
  final String cStreetD;
  final String cHouseNumberD;
  final String cPostalCodeD;
  final String cCityD;
  final String cStateD;
  final String? cCountryDId;
  final String cMail;
  final String cPhone;
  final String cWeb;
  final String cSocialMedia;
  final double cLat;
  final double cLong;
  final String cNote;
  final double cTotalValueEur;
  final double cTotalValueUsd;
  final int cLastModified;

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      cId: _str(map['c_id']),
      cCompany: _str(map['c_company'], fallback: '-'),
      cDealer: _bool(map['c_dealer']),
      cVat: _bool(map['c_vat']),
      cVatId: _str(map['c_vat_id'], fallback: '-'),
      cLastName: _str(map['c_last_name']),
      cFirstName: _str(map['c_first_name']),
      cCareofB: _str(map['c_careof_b'], fallback: '-'),
      cStreetB: _str(map['c_street_b']),
      cHouseNumberB: _str(map['c_house_number_b']),
      cPostalCodeB: _str(map['c_postal_code_b']),
      cCityB: _str(map['c_city_b']),
      cStateB: _str(map['c_state_b'], fallback: '-'),
      cCountryBId: _nullableStr(map['c_country_b_id']),
      cCareofD: _str(map['c_careof_d'], fallback: '-'),
      cStreetD: _str(map['c_street_d']),
      cHouseNumberD: _str(map['c_house_number_d']),
      cPostalCodeD: _str(map['c_postal_code_d']),
      cCityD: _str(map['c_city_d']),
      cStateD: _str(map['c_state_d'], fallback: '-'),
      cCountryDId: _nullableStr(map['c_country_d_id']),
      cMail: _str(map['c_mail'], fallback: '-'),
      cPhone: _str(map['c_phone'], fallback: '-'),
      cWeb: _str(map['c_web'], fallback: '-'),
      cSocialMedia: _str(map['c_social_media'], fallback: '-'),
      cLat: _double(map['c_lat']),
      cLong: _double(map['c_long']),
      cNote: _str(map['c_note'], fallback: '-'),
      cTotalValueEur: _double(map['c_total_value_eur']),
      cTotalValueUsd: _double(map['c_total_value_usd']),
      cLastModified: _int(map['c_last_modified']),
    );
  }

  factory Customer.fromCsvRow(Map<String, String> row) {
    return Customer(
      cId: _str(row['c_id']),
      cCompany: _str(row['c_company'], fallback: '-'),
      cDealer: _bool(row['c_dealer']),
      cVat: _bool(row['c_vat']),
      cVatId: _str(row['c_vat_id'], fallback: '-'),
      cLastName: _str(row['c_last_name']),
      cFirstName: _str(row['c_first_name']),
      cCareofB: _str(row['c_careof_b'], fallback: '-'),
      cStreetB: _str(row['c_street_b']),
      cHouseNumberB: _str(row['c_house_number_b']),
      cPostalCodeB: _str(row['c_postal_code_b']),
      cCityB: _str(row['c_city_b']),
      cStateB: _str(row['c_state_b'], fallback: '-'),
      cCountryBId: _nullableStr(row['c_country_b_id']),
      cCareofD: _str(row['c_careof_d'], fallback: '-'),
      cStreetD: _str(row['c_street_d']),
      cHouseNumberD: _str(row['c_house_number_d']),
      cPostalCodeD: _str(row['c_postal_code_d']),
      cCityD: _str(row['c_city_d']),
      cStateD: _str(row['c_state_d'], fallback: '-'),
      cCountryDId: _nullableStr(row['c_country_d_id']),
      cMail: _str(row['c_mail'], fallback: '-'),
      cPhone: _str(row['c_phone'], fallback: '-'),
      cWeb: _str(row['c_web'], fallback: '-'),
      cSocialMedia: _str(row['c_social_media'], fallback: '-'),
      cLat: _double(row['c_lat']),
      cLong: _double(row['c_long']),
      cNote: _str(row['c_note'], fallback: '-'),
      cTotalValueEur: _double(row['c_total_value_eur']),
      cTotalValueUsd: _double(row['c_total_value_usd']),
      cLastModified: _int(row['c_last_modified']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'c_id': cId,
      'c_company': cCompany,
      'c_dealer': cDealer ? 1 : 0,
      'c_vat': cVat ? 1 : 0,
      'c_vat_id': cVatId,
      'c_last_name': cLastName,
      'c_first_name': cFirstName,
      'c_careof_b': cCareofB,
      'c_street_b': cStreetB,
      'c_house_number_b': cHouseNumberB,
      'c_postal_code_b': cPostalCodeB,
      'c_city_b': cCityB,
      'c_state_b': cStateB,
      'c_country_b_id': cCountryBId,
      'c_careof_d': cCareofD,
      'c_street_d': cStreetD,
      'c_house_number_d': cHouseNumberD,
      'c_postal_code_d': cPostalCodeD,
      'c_city_d': cCityD,
      'c_state_d': cStateD,
      'c_country_d_id': cCountryDId,
      'c_mail': cMail,
      'c_phone': cPhone,
      'c_web': cWeb,
      'c_social_media': cSocialMedia,
      'c_lat': cLat,
      'c_long': cLong,
      'c_note': cNote,
      'c_total_value_eur': cTotalValueEur,
      'c_total_value_usd': cTotalValueUsd,
      'c_last_modified': cLastModified,
    };
  }

  static String _str(Object? value, {String fallback = ''}) {
    final stringValue = value?.toString().trim();
    if (stringValue == null || stringValue.isEmpty) {
      return fallback;
    }
    return stringValue;
  }

  static String? _nullableStr(Object? value) {
    final stringValue = value?.toString().trim();
    if (stringValue == null || stringValue.isEmpty || stringValue == '-') {
      return null;
    }
    return stringValue;
  }

  static bool _bool(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'ja';
  }

  static double _double(Object? value) {
    final raw = value?.toString().trim().replaceAll(',', '.');
    return double.tryParse(raw ?? '') ?? 0;
  }

  static int _int(Object? value) {
    final raw = value?.toString().trim();
    return int.tryParse(raw ?? '') ?? 0;
  }
}
