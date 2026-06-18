import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pdf Spaltenbreiten fuer Kernfelder bleiben stabil', () {
    // Short technical and numeric columns - very compact
    expect(cataloguePdfColumnFlexForFieldKey('ic_id'), 0.5);
    expect(cataloguePdfColumnFlexForFieldKey('ic_ic'), 0.5);
    expect(cataloguePdfColumnFlexForFieldKey('ic_stock'), 0.5);
    expect(cataloguePdfColumnFlexForFieldKey('ic_weight'), 0.6);
    expect(cataloguePdfColumnFlexForFieldKey('ic_hts'), 0.6);

    // Price columns - compact
    expect(cataloguePdfColumnFlexForFieldKey('ic_price_net'), 0.7);
    expect(cataloguePdfColumnFlexForFieldKey('ic_price_gross_19'), 0.7);
    expect(cataloguePdfColumnFlexForFieldKey('ic_price_wholesale_net'), 0.7);
    expect(cataloguePdfColumnFlexForFieldKey('ic_purchase_price_net'), 0.7);

    // German description heavily prioritized: maximum width
    expect(cataloguePdfColumnFlexForFieldKey('ic_description_de_long'), 1.8);

    // Text columns - moderately compact
    expect(cataloguePdfColumnFlexForFieldKey('ic_description_en_long'), 1.2);
    expect(cataloguePdfColumnFlexForFieldKey('ic_note'), 1.2);
    expect(cataloguePdfColumnFlexForFieldKey('ic_image_path'), 1.2);
    expect(cataloguePdfColumnFlexForFieldKey('ic_source_of_supply'), 1.2);

    // Typical short text identifiers - compact
    expect(cataloguePdfColumnFlexForFieldKey('ic_idi'), 0.9);
    expect(cataloguePdfColumnFlexForFieldKey('ic_ide'), 0.9);
    expect(cataloguePdfColumnFlexForFieldKey('ic_idv'), 0.9);

    // Default for unknown fields
    expect(cataloguePdfColumnFlexForFieldKey('ic_some_unknown_field'), 0.85);
  });

  test('pdf Spaltenbreiten-Anteile ermoeglicht ausgewogene Layouts', () {
    // Narrow core fields
    final narrowFields = ['ic_id', 'ic_weight', 'ic_hts'];
    final narrowTotal = narrowFields.fold<double>(
      0,
      (sum, key) => sum + cataloguePdfColumnFlexForFieldKey(key),
    );
    expect(narrowTotal, lessThan(3.0));

    // Mix with broader fields
    final broadFields = ['ic_description_de_long', 'ic_description_en_long'];
    final broadTotal = broadFields.fold<double>(
      0,
      (sum, key) => sum + cataloguePdfColumnFlexForFieldKey(key),
    );
    expect(broadTotal, greaterThan(2.0));
  });
}
