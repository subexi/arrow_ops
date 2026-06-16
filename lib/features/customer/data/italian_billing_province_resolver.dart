String resolveItalianBillingProvince({
  required String? countryCode,
  required String? currentState,
  required String? city,
}) {
  final normalizedState = currentState?.trim();

  final isItaly = isItalyCountry(countryCode);
  if (!isItaly) {
    return normalizedState == null || normalizedState.isEmpty ? '-' : normalizedState;
  }

  if (normalizedState != null && normalizedState.isNotEmpty && normalizedState != '-') {
    final canonicalFromState = _canonicalProvinceFromText(normalizedState);
    if (canonicalFromState != null) {
      return canonicalFromState;
    }
    return normalizedState;
  }

  final canonicalFromCityText = _canonicalProvinceFromText(city);
  if (canonicalFromCityText != null) {
    return canonicalFromCityText;
  }

  final cityCandidates = _normalizeCityCandidates(city);
  if (cityCandidates.isEmpty) {
    return '-';
  }

  for (final candidate in cityCandidates) {
    final province = _provinceByCity[candidate];
    if (province != null) {
      return province;
    }

    final provinceByName = _provinceFromName(candidate);
    if (provinceByName != null) {
      return provinceByName;
    }
  }

  return '-';
}

String appendItalianProvinceAbbreviationToCity({
  required String? city,
  required String? administrativeUnit,
}) {
  final trimmedCity = city?.trim() ?? '';
  if (trimmedCity.isEmpty || trimmedCity == '-') {
    return trimmedCity;
  }

  final provinceCode = _italianProvinceCodeFromAdministrativeUnit(administrativeUnit);
  if (provinceCode == null) {
    return trimmedCity;
  }

  final cleanedCity = _stripTrailingAdministrativeSuffixes(
    trimmedCity,
    patterns: [RegExp(r'\s*\([A-Za-z]{2}\)\s*$')],
  );
  if (cleanedCity.isEmpty) {
    return trimmedCity;
  }

  return '$cleanedCity ($provinceCode)';
}

String? _italianProvinceCodeFromAdministrativeUnit(String? administrativeUnit) {
  final trimmed = administrativeUnit?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == '-') {
    return null;
  }

  final match = RegExp(r'^([A-Za-z]{2})-').firstMatch(trimmed);
  return match?.group(1)?.toUpperCase();
}

String resolveUSStateAdministrativeUnit({
  required String? countryCode,
  required String? currentState,
  String? city,
}) {
  final normalizedState = currentState?.trim();
  final isUs = isUsCountry(countryCode);
  if (!isUs) {
    return normalizedState == null || normalizedState.isEmpty ? '-' : normalizedState;
  }

  if (normalizedState != null && normalizedState.isNotEmpty && normalizedState != '-') {
    final canonical = _canonicalUSStateFromText(normalizedState);
    return canonical ?? normalizedState;
  }

  final canonicalFromCity = _canonicalUSStateFromText(city ?? '');
  return canonicalFromCity ?? '-';
}

String appendUSStateAbbreviationToCity({
  required String? city,
  required String? administrativeUnit,
}) {
  final trimmedCity = city?.trim() ?? '';
  if (trimmedCity.isEmpty || trimmedCity == '-') {
    return trimmedCity;
  }

  final stateCode = _provinceCodeFromAdministrativeUnit(administrativeUnit);
  if (stateCode == null || !_usStateNameByCode.containsKey(stateCode)) {
    return trimmedCity;
  }

  final cleanedCity = _stripTrailingAdministrativeSuffixes(
    trimmedCity,
    patterns: [
      RegExp(r'\s*\([A-Za-z]{2}\)\s*$'),
      RegExp(r'\s*,\s*[A-Za-z]{2}\s*$'),
    ],
  );
  if (cleanedCity.isEmpty) {
    return trimmedCity;
  }

  return '$cleanedCity, $stateCode';
}

String _stripTrailingAdministrativeSuffixes(
  String value, {
  required List<RegExp> patterns,
}) {
  var current = value.trim();
  var changed = true;

  while (changed && current.isNotEmpty) {
    changed = false;
    for (final pattern in patterns) {
      final next = current.replaceFirst(pattern, '').trim();
      if (next != current) {
        current = next;
        changed = true;
      }
    }
  }

  return current;
}

bool isItalyCountry(String? countryCode) {
  final normalizedCountry = countryCode?.trim().toLowerCase();
  return normalizedCountry == 'it' ||
      normalizedCountry == 'italy' ||
      normalizedCountry == 'italien';
}

bool isUsCountry(String? countryCode) {
  final normalizedCountry = countryCode?.trim().toLowerCase();
  return normalizedCountry == 'us' ||
      normalizedCountry == 'usa' ||
      normalizedCountry == 'united states' ||
      normalizedCountry == 'united states of america' ||
      normalizedCountry == 'vereinigte staaten';
}

bool isAustraliaCountry(String? countryCode) {
  final normalizedCountry = countryCode?.trim().toLowerCase();
  return normalizedCountry == 'au' ||
      normalizedCountry == 'australia' ||
      normalizedCountry == 'australien';
}

bool isSwitzerlandCountry(String? countryCode) {
  final normalizedCountry = countryCode?.trim().toLowerCase();
  return normalizedCountry == 'ch' ||
      normalizedCountry == 'switzerland' ||
      normalizedCountry == 'schweiz' ||
      normalizedCountry == 'suisse' ||
      normalizedCountry == 'svizzera';
}

String resolveAustralianStateAdministrativeUnit({
  required String? countryCode,
  required String? currentState,
  String? city,
}) {
  final normalizedState = currentState?.trim();
  final isAustralia = isAustraliaCountry(countryCode);
  if (!isAustralia) {
    return normalizedState == null || normalizedState.isEmpty ? '-' : normalizedState;
  }

  if (normalizedState != null && normalizedState.isNotEmpty && normalizedState != '-') {
    final canonical = _canonicalAustralianStateFromText(normalizedState);
    return canonical ?? normalizedState;
  }

  final canonicalFromCity = _canonicalAustralianStateFromText(city ?? '');
  return canonicalFromCity ?? '-';
}

String resolveSwissCantonAdministrativeUnit({
  required String? countryCode,
  required String? currentState,
  String? city,
}) {
  final normalizedState = currentState?.trim();
  final isSwitzerland = isSwitzerlandCountry(countryCode);
  if (!isSwitzerland) {
    return normalizedState == null || normalizedState.isEmpty ? '-' : normalizedState;
  }

  if (normalizedState != null && normalizedState.isNotEmpty && normalizedState != '-') {
    final canonical = _canonicalSwissCantonFromText(normalizedState);
    return canonical ?? normalizedState;
  }

  final canonicalFromCity = _canonicalSwissCantonFromText(city ?? '');
  return canonicalFromCity ?? '-';
}

String? _provinceCodeFromAdministrativeUnit(String? administrativeUnit) {
  final trimmed = administrativeUnit?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == '-') {
    return null;
  }

  final match = RegExp(r'^([A-Za-z]{2})\b').firstMatch(trimmed);
  return match?.group(1)?.toUpperCase();
}

String? _canonicalUSStateFromText(String text) {
  final normalized = _normalizeCityToken(text);
  if (normalized == null) {
    return null;
  }

  final directCode = normalized.toUpperCase();
  final directName = _usStateNameByCode[directCode];
  if (directName != null) {
    return '$directCode-$directName';
  }

  final matches = RegExp(r'\b([a-z]{2})\b').allMatches(normalized);
  for (final match in matches) {
    final code = match.group(1)?.toUpperCase();
    if (code == null) {
      continue;
    }
    final name = _usStateNameByCode[code];
    if (name != null) {
      return '$code-$name';
    }
  }

  for (final entry in _usStateNameByCode.entries) {
    final normalizedStateName = _normalizeCityToken(entry.value) ?? '';
    if (normalizedStateName == normalized) {
      return '${entry.key}-${entry.value}';
    }
  }

  return null;
}

String? _canonicalAustralianStateFromText(String text) {
  final normalized = _normalizeCityToken(text);
  if (normalized == null) {
    return null;
  }

  final directCode = normalized.toUpperCase();
  final directName = _auStateNameByCode[directCode];
  if (directName != null) {
    return '$directCode-$directName';
  }

  final matches = RegExp(r'\b([a-z]{2,3})\b').allMatches(normalized);
  for (final match in matches) {
    final code = match.group(1)?.toUpperCase();
    if (code == null) {
      continue;
    }
    final name = _auStateNameByCode[code];
    if (name != null) {
      return '$code-$name';
    }
  }

  for (final entry in _auStateNameByCode.entries) {
    final normalizedStateName = _normalizeCityToken(entry.value) ?? '';
    if (normalizedStateName == normalized) {
      return '${entry.key}-${entry.value}';
    }
  }

  return null;
}

String? _canonicalSwissCantonFromText(String text) {
  final normalized = _normalizeCityToken(text);
  if (normalized == null) {
    return null;
  }

  final directCode = normalized.toUpperCase();
  final directName = _chCantonNameByCode[directCode];
  if (directName != null) {
    return '$directCode-$directName';
  }

  final isoMatches = RegExp(r'\bch\s*([a-z]{2})\b').allMatches(normalized);
  for (final match in isoMatches) {
    final code = match.group(1)?.toUpperCase();
    if (code == null) {
      continue;
    }
    final name = _chCantonNameByCode[code];
    if (name != null) {
      return '$code-$name';
    }
  }

  final matches = RegExp(r'\b([a-z]{2})\b').allMatches(normalized);
  for (final match in matches) {
    final code = match.group(1)?.toUpperCase();
    if (code == null) {
      continue;
    }
    final name = _chCantonNameByCode[code];
    if (name != null) {
      return '$code-$name';
    }
  }

  for (final entry in _chCantonNameByCode.entries) {
    final normalizedName = _normalizeCityToken(entry.value) ?? '';
    if (normalizedName == normalized) {
      return '${entry.key}-${entry.value}';
    }
  }

  return null;
}

String? _canonicalProvinceFromText(String? text) {
  final normalized = _normalizeCityToken(text ?? '');
  if (normalized == null) {
    return null;
  }

  final directCode = normalized.toUpperCase();
  final directName = _provinceNameByCode[directCode];
  if (directName != null) {
    return '$directCode-$directName';
  }

  final matches = RegExp(r'\b([a-z]{2})\b').allMatches(normalized);
  for (final match in matches) {
    final code = match.group(1)?.toUpperCase();
    if (code == null) {
      continue;
    }
    final name = _provinceNameByCode[code];
    if (name != null) {
      return '$code-$name';
    }
  }

  return null;
}

List<String> _normalizeCityCandidates(String? city) {
  final raw = city?.trim().toLowerCase();
  if (raw == null || raw.isEmpty || raw == '-') {
    return const [];
  }

  final withoutParentheses = raw.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  final segments = withoutParentheses.split('/');

  final candidates = <String>{};

  void addCandidate(String value) {
    final normalized = _normalizeCityToken(value);
    if (normalized != null) {
      candidates.add(normalized);
    }
  }

  addCandidate(withoutParentheses);
  for (final segment in segments) {
    addCandidate(segment);
  }

  return candidates.toList(growable: false);
}

String? _normalizeCityToken(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty || trimmed == '-') {
    return null;
  }

  final normalized = trimmed
      .replaceAll('à', 'a')
      .replaceAll('á', 'a')
      .replaceAll('è', 'e')
      .replaceAll('é', 'e')
      .replaceAll('ì', 'i')
      .replaceAll('í', 'i')
      .replaceAll('ò', 'o')
      .replaceAll('ó', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('ú', 'u')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (normalized.isEmpty || normalized == '-') {
    return null;
  }

  return normalized;
}

const Map<String, String> _provinceByCity = {
  'merano': 'BZ-Bolzano',
  'meran': 'BZ-Bolzano',
  'bolzano': 'BZ-Bolzano',
  'bozen': 'BZ-Bolzano',
  'milano': 'MI-Milano',
  'milan': 'MI-Milano',
  'alessandria': 'AL-Alessandria',
  'allessandra': 'AL-Alessandria',
  'cassine': 'AL-Alessandria',
  'piacenza': 'PC-Piacenza',
  'oberbozen': 'BZ-Bolzano',
  'ritten': 'BZ-Bolzano',
  'castiglione della pescaia': 'GR-Grosseto',
  'castiglione bella pescaia': 'GR-Grosseto',
  'gardone val trompia': 'BS-Brescia',
  'san giuseppe di cassola': 'VI-Vicenza',
  'cassola': 'VI-Vicenza',
};

const Map<String, String> _provinceNameByCode = {
  'AG': 'Agrigento',
  'AL': 'Alessandria',
  'AN': 'Ancona',
  'AO': 'Aosta',
  'AP': 'Ascoli Piceno',
  'AQ': "L'Aquila",
  'AR': 'Arezzo',
  'AT': 'Asti',
  'AV': 'Avellino',
  'BA': 'Bari',
  'BG': 'Bergamo',
  'BI': 'Biella',
  'BZ': 'Bolzano',
  'BL': 'Belluno',
  'BN': 'Benevento',
  'BO': 'Bologna',
  'BR': 'Brindisi',
  'BS': 'Brescia',
  'BT': 'Barletta-Andria-Trani',
  'CA': 'Cagliari',
  'CB': 'Campobasso',
  'CE': 'Caserta',
  'CH': 'Chieti',
  'CL': 'Caltanissetta',
  'CN': 'Cuneo',
  'CO': 'Como',
  'CR': 'Cremona',
  'CS': 'Cosenza',
  'CT': 'Catania',
  'CZ': 'Catanzaro',
  'EN': 'Enna',
  'FC': 'Forli-Cesena',
  'FE': 'Ferrara',
  'FG': 'Foggia',
  'FI': 'Firenze',
  'FM': 'Fermo',
  'FR': 'Frosinone',
  'GE': 'Genova',
  'GO': 'Gorizia',
  'GR': 'Grosseto',
  'IM': 'Imperia',
  'IS': 'Isernia',
  'KR': 'Crotone',
  'LC': 'Lecco',
  'LE': 'Lecce',
  'LI': 'Livorno',
  'LO': 'Lodi',
  'LT': 'Latina',
  'LU': 'Lucca',
  'MB': 'Monza e Brianza',
  'MC': 'Macerata',
  'ME': 'Messina',
  'MI': 'Milano',
  'MN': 'Mantova',
  'MO': 'Modena',
  'MS': 'Massa-Carrara',
  'MT': 'Matera',
  'NA': 'Napoli',
  'NO': 'Novara',
  'NU': 'Nuoro',
  'OR': 'Oristano',
  'PA': 'Palermo',
  'PD': 'Padova',
  'PE': 'Pescara',
  'PG': 'Perugia',
  'PI': 'Pisa',
  'PN': 'Pordenone',
  'PC': 'Piacenza',
  'PO': 'Prato',
  'PR': 'Parma',
  'PT': 'Pistoia',
  'PU': 'Pesaro e Urbino',
  'PV': 'Pavia',
  'PZ': 'Potenza',
  'RA': 'Ravenna',
  'RC': 'Reggio Calabria',
  'RE': 'Reggio Emilia',
  'RG': 'Ragusa',
  'RI': 'Rieti',
  'RM': 'Roma',
  'RN': 'Rimini',
  'RO': 'Rovigo',
  'SA': 'Salerno',
  'SI': 'Siena',
  'SO': 'Sondrio',
  'SP': 'La Spezia',
  'SR': 'Siracusa',
  'SS': 'Sassari',
  'SU': 'Sud Sardegna',
  'SV': 'Savona',
  'TA': 'Taranto',
  'TE': 'Teramo',
  'TN': 'Trento',
  'TO': 'Torino',
  'TP': 'Trapani',
  'TR': 'Terni',
  'TS': 'Trieste',
  'TV': 'Treviso',
  'UD': 'Udine',
  'VA': 'Varese',
  'VB': 'Verbano-Cusio-Ossola',
  'VC': 'Vercelli',
  'VE': 'Venezia',
  'VI': 'Vicenza',
  'VR': 'Verona',
  'VS': 'Medio Campidano',
  'VT': 'Viterbo',
  'VV': 'Vibo Valentia',
};

const Map<String, String> _usStateNameByCode = {
  'AL': 'Alabama',
  'AK': 'Alaska',
  'AZ': 'Arizona',
  'AR': 'Arkansas',
  'CA': 'California',
  'CO': 'Colorado',
  'CT': 'Connecticut',
  'DE': 'Delaware',
  'FL': 'Florida',
  'GA': 'Georgia',
  'HI': 'Hawaii',
  'ID': 'Idaho',
  'IL': 'Illinois',
  'IN': 'Indiana',
  'IA': 'Iowa',
  'KS': 'Kansas',
  'KY': 'Kentucky',
  'LA': 'Louisiana',
  'ME': 'Maine',
  'MD': 'Maryland',
  'MA': 'Massachusetts',
  'MI': 'Michigan',
  'MN': 'Minnesota',
  'MS': 'Mississippi',
  'MO': 'Missouri',
  'MT': 'Montana',
  'NE': 'Nebraska',
  'NV': 'Nevada',
  'NH': 'New Hampshire',
  'NJ': 'New Jersey',
  'NM': 'New Mexico',
  'NY': 'New York',
  'NC': 'North Carolina',
  'ND': 'North Dakota',
  'OH': 'Ohio',
  'OK': 'Oklahoma',
  'OR': 'Oregon',
  'PA': 'Pennsylvania',
  'RI': 'Rhode Island',
  'SC': 'South Carolina',
  'SD': 'South Dakota',
  'TN': 'Tennessee',
  'TX': 'Texas',
  'UT': 'Utah',
  'VT': 'Vermont',
  'VA': 'Virginia',
  'WA': 'Washington',
  'WV': 'West Virginia',
  'WI': 'Wisconsin',
  'WY': 'Wyoming',
  'DC': 'District of Columbia',
};

const Map<String, String> _auStateNameByCode = {
  'NSW': 'New South Wales',
  'VIC': 'Victoria',
  'QLD': 'Queensland',
  'SA': 'South Australia',
  'WA': 'Western Australia',
  'TAS': 'Tasmania',
  'NT': 'Northern Territory',
  'ACT': 'Australian Capital Territory',
};

const Map<String, String> _chCantonNameByCode = {
  'AG': 'Aargau',
  'AI': 'Appenzell Innerrhoden',
  'AR': 'Appenzell Ausserrhoden',
  'BE': 'Bern',
  'BL': 'Basel-Landschaft',
  'BS': 'Basel-Stadt',
  'FR': 'Fribourg',
  'GE': 'Geneve',
  'GL': 'Glarus',
  'GR': 'Graubunden',
  'JU': 'Jura',
  'LU': 'Luzern',
  'NE': 'Neuchatel',
  'NW': 'Nidwalden',
  'OW': 'Obwalden',
  'SG': 'St. Gallen',
  'SH': 'Schaffhausen',
  'SO': 'Solothurn',
  'SZ': 'Schwyz',
  'TG': 'Thurgau',
  'TI': 'Ticino',
  'UR': 'Uri',
  'VD': 'Vaud',
  'VS': 'Valais',
  'ZG': 'Zug',
  'ZH': 'Zurich',
};

String? _provinceFromName(String normalizedName) {
  for (final entry in _provinceNameByCode.entries) {
    final code = entry.key;
    final normalizedProvinceName = _normalizeCityToken(entry.value) ?? '';
    if (normalizedProvinceName == normalizedName) {
      return '$code-${entry.value}';
    }
  }
  return null;
}
