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
          'Σ EK netto (EUR)',
          'Σ Verkauf netto (EUR)',
          'Marge EUR',
        ]),
      );
    });
  });

  group('wareinsatzPdfColumnFlexes', () {
    test('maps all-scope columns in expected order', () {
      expect(
        wareinsatzPdfColumnFlexes(
          showMengeOhneBomColumn: true,
          showBomMengeColumn: true,
          showGesamtmengeColumn: true,
          showFinancialColumns: false,
        ),
        equals(const [0.9, 3.4, 1.0, 1.0, 1.0]),
      );
    });

    test('maps bom-only scope columns in expected order', () {
      expect(
        wareinsatzPdfColumnFlexes(
          showMengeOhneBomColumn: false,
          showBomMengeColumn: true,
          showGesamtmengeColumn: false,
          showFinancialColumns: false,
        ),
        equals(const [0.9, 3.4, 1.0]),
      );
    });

    test('maps without-bom scope columns with financial block aligned', () {
      expect(
        wareinsatzPdfColumnFlexes(
          showMengeOhneBomColumn: true,
          showBomMengeColumn: false,
          showGesamtmengeColumn: false,
          showFinancialColumns: true,
        ),
        equals(const [0.9, 3.4, 1.0, 1.1, 1.2, 1.2, 1.1]),
      );
    });
  });
}
