class PayPalFeeRules {
  const PayPalFeeRules._();

  static const double fixedFeeEur = 0.36;
  static const double rateDe = 0.0249;
  static const double rateEu = 0.0249;
  static const double rateUk = 0.03774;
  static const double rateUsCa = 0.04453;
  static const double rateAu = 0.05475;
  static const double rateRest = 0.0549;

  static const Set<String> _deCountryTokens = <String>{
    'DE',
    'DEU',
    'GERMANY',
    'DEUTSCHLAND',
  };

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

  static const Set<String> _auCountryTokens = <String>{
    'AU',
    'AUS',
    'AUSTRALIA',
    'AUSTRALIEN',
  };

  static const Set<String> _euCountryTokens = <String>{
    'AT',
    'AUT',
    'BE',
    'BEL',
    'BG',
    'BGR',
    'HR',
    'HRV',
    'CY',
    'CYP',
    'CZ',
    'CZE',
    'DK',
    'DNK',
    'EE',
    'EST',
    'FI',
    'FIN',
    'FR',
    'FRA',
    'GR',
    'GRC',
    'EL',
    'HU',
    'HUN',
    'IE',
    'IRL',
    'IT',
    'ITA',
    'LV',
    'LVA',
    'LT',
    'LTU',
    'LU',
    'LUX',
    'MT',
    'MLT',
    'NL',
    'NLD',
    'NETHERLANDS',
    'HOLLAND',
    'NIEDERLANDE',
    'PL',
    'POL',
    'PT',
    'PRT',
    'RO',
    'ROU',
    'SK',
    'SVK',
    'SI',
    'SVN',
    'ES',
    'ESP',
    'SE',
    'SWE',
  };

  static double rateByCountry(String countryToken) {
    final token = countryToken.trim().toUpperCase();

    if (_deCountryTokens.contains(token)) {
      return rateDe;
    }
    if (_ukCountryTokens.contains(token)) {
      return rateUk;
    }
    if (_usCaCountryTokens.contains(token)) {
      return rateUsCa;
    }
    if (_auCountryTokens.contains(token)) {
      return rateAu;
    }
    if (_euCountryTokens.contains(token)) {
      return rateEu;
    }

    return rateRest;
  }

  static double feeFromTotalEur({
    required double totalEur,
    required String countryToken,
  }) {
    final rate = rateByCountry(countryToken);
    final fee = (totalEur * rate) + fixedFeeEur;
    return (fee * 100).roundToDouble() / 100;
  }
}
