class PayPalFeeRules {
  const PayPalFeeRules._();

  // Empfängerland DE, Währung EUR, Geschäftszahlung.
  // Gebührenbasis: Warenwert brutto + Versandkosten.
  static const double fixedFeeEur = 0.36;
  static const double rateEea = 0.0249;
  static const double rateUk = 0.03774;
  static const double rateUsCa = 0.04453;
  static const double rateRest = 0.0549;

  static const Set<String> _ukCountryTokens = <String>{
    'GB',
    'UK',
    'GBR',
    'UNITED KINGDOM',
    'VEREINIGTES KÖNIGREICH',
    'VEREINIGTES KOENIGREICH',
  };

  static const Set<String> _usCaCountryTokens = <String>{
    'US',
    'USA',
    'UNITED STATES',
    'VEREINIGTE STAATEN',
    'CA',
    'CAN',
    'CANADA',
  };

  static const Set<String> _eeaCountryTokens = <String>{
    'AT',
    'AUT',
    'AUSTRIA',
    'BE',
    'BEL',
    'BELGIUM',
    'BG',
    'BGR',
    'BULGARIA',
    'HR',
    'HRV',
    'CROATIA',
    'CY',
    'CYP',
    'CYPRUS',
    'CZ',
    'CZE',
    'CZECH REPUBLIC',
    'DK',
    'DNK',
    'DENMARK',
    'EE',
    'EST',
    'ESTONIA',
    'FI',
    'FIN',
    'FINLAND',
    'FR',
    'FRA',
    'FRANCE',
    'GR',
    'GRC',
    'GREECE',
    'EL',
    'HU',
    'HUN',
    'HUNGARY',
    'IE',
    'IRL',
    'IRELAND',
    'IT',
    'ITA',
    'ITALY',
    'ITALIA',
    'LV',
    'LVA',
    'LATVIA',
    'LT',
    'LTU',
    'LITHUANIA',
    'LU',
    'LUX',
    'LUXEMBOURG',
    'MT',
    'MLT',
    'MALTA',
    'NL',
    'NLD',
    'NETHERLANDS',
    'HOLLAND',
    'NIEDERLANDE',
    'PL',
    'POL',
    'POLAND',
    'PT',
    'PRT',
    'PORTUGAL',
    'RO',
    'ROU',
    'ROMANIA',
    'SK',
    'SVK',
    'SLOVAKIA',
    'SI',
    'SVN',
    'SLOVENIA',
    'ES',
    'ESP',
    'SPAIN',
    'SE',
    'SWE',
    'SWEDEN',
    'NO',
    'NOR',
    'NORWAY',
    'IS',
    'ISL',
    'ICELAND',
    'LI',
    'LIE',
    'LIECHTENSTEIN',
  };

  static double rateByCountry(String countryToken) {
    final token = countryToken.trim().toUpperCase();

    if (_ukCountryTokens.contains(token)) {
      return rateUk;
    }
    if (_usCaCountryTokens.contains(token)) {
      return rateUsCa;
    }
    if (_eeaCountryTokens.contains(token)) {
      return rateEea;
    }

    return rateRest;
  }

  static double feeFromBaseAmountEur({
    required double baseAmountEur,
    required String countryToken,
  }) {
    if (baseAmountEur <= 0) {
      return 0;
    }
    final rate = rateByCountry(countryToken);
    final fee = (baseAmountEur * rate) + fixedFeeEur;
    return (fee * 100).roundToDouble() / 100;
  }
}
