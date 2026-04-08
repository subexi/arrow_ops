import 'package:csv/csv.dart';

import '../domain/country_tld.dart';

class CountryCsvService {
  List<CountryTld> importCountries(String csvContent) {
    final rows = csv.decode(csvContent);
    if (rows.isEmpty) {
      return const [];
    }

    final firstRow = rows.first.map((e) => _normalize(e)).toList();
    final hasHeader = firstRow.contains('co_tld') || firstRow.contains('tld');

    final tldIndex = hasHeader ? _findIndex(firstRow, const ['co_tld', 'tld']) : 0;
    final nameIndex = hasHeader ? _findIndex(firstRow, const ['co_name', 'name']) : 1;

    final startIndex = hasHeader ? 1 : 0;
    final result = <CountryTld>[];

    for (var i = startIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) {
        continue;
      }

      final rawTld = _at(row, tldIndex);
      final rawName = _at(row, nameIndex);

      final tld = _cleanCode(rawTld);
      if (tld == null) {
        continue;
      }

      final name = rawName.isEmpty ? tld.toUpperCase() : rawName;
      result.add(CountryTld(coTld: tld, coName: name));
    }

    return result;
  }

  int _findIndex(List<String> headers, List<String> keys) {
    for (final key in keys) {
      final index = headers.indexOf(key);
      if (index >= 0) {
        return index;
      }
    }
    return keys.first == 'co_tld' || keys.first == 'tld' ? 0 : 1;
  }

  String _at(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) {
      return '';
    }
    return row[index].toString().trim();
  }

  String _normalize(Object? value) {
    final v = value?.toString().trim().toLowerCase() ?? '';
    return v.startsWith('\uFEFF') ? v.substring(1) : v;
  }

  String? _cleanCode(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty || normalized == '-') {
      return null;
    }
    return normalized;
  }
}
