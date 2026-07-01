class PayPalFeeRules {
  const PayPalFeeRules._();

  // Empfängerland DE, Währung EUR, Geschäftszahlung.
  // Gebührenbasis: Warenwert brutto + Versandkosten.
  static const double fixedFeeEur = 0.35;
  static const double rateEea = 0.0249;
  static const double rateUk = 0.0378;
  static const double rateUsCa = 0.0448;
  static const double rateRest = 0.0548;

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
    'DE',
    'DEU',
    'GERMANY',
    'DEUTSCHLAND',
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
    'CZECHIA',
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

  static double requiredReceivedAmountFromNetTargetEur({
    required double netTargetEur,
    required String countryToken,
  }) {
    if (netTargetEur <= 0) {
      return 0;
    }

    final rate = rateByCountry(countryToken);
    final denominator = 1 - rate;
    if (denominator <= 0) {
      return 0;
    }

    final required = (netTargetEur + fixedFeeEur) / denominator;
    return (required * 100).roundToDouble() / 100;
  }

  static double feeFromNetTargetEur({
    required double netTargetEur,
    required String countryToken,
  }) {
    if (netTargetEur <= 0) {
      return 0;
    }

    final required = requiredReceivedAmountFromNetTargetEur(
      netTargetEur: netTargetEur,
      countryToken: countryToken,
    );
    final fee = required - netTargetEur;
    return (fee * 100).roundToDouble() / 100;
  }
}
