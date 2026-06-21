import 'package:arrow_ops/features/analytics/presentation/analytics_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wareinsatzExportHeaders', () {
    test('shows all quantity headers in all-position scope', () {
      expect(
        wareinsatzExportHeaders(WareinsatzScope.all),
        equals(const [
          'Bezeichnung',
          'Beschreibung',
          'Menge ohne BOM',
          'BOM-Menge',
          'Gesamtmenge',
        ]),
      );
    });

    test('shows only BOM quantity in bom-only scope', () {
      expect(
        wareinsatzExportHeaders(WareinsatzScope.bomOnly),
        equals(const [
          'Bezeichnung',
          'Beschreibung',
          'BOM-Menge',
        ]),
      );
    });

    test('shows quantity and EUR headers in without-bom scope', () {
      expect(
        wareinsatzExportHeaders(WareinsatzScope.withoutBom),
        equals(const [
          'Bezeichnung',
          'Beschreibung',
          'Menge ohne BOM',
          'EK netto (EUR)',
          'Wert netto (EUR)',
          'Verkauf netto (EUR)',
          'Marge EUR',
        ]),
      );
    });
  });
}
