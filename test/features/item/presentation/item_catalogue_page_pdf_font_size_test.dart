import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pdf Zellschrift ohne Hard-No-Wrap bleibt Standardgroesse', () {
    final size = cataloguePdfCellFontSizeForFieldKeys(const [
      'ic_description_de_long',
      'ic_description_en_long',
      'ic_note',
      'ic_image_path',
    ]);

    expect(size, 6.5);
  });

  test('pdf Zellschrift mit Hard-No-Wrap reagiert auf Feldanzahl', () {
    final mediumSize = cataloguePdfCellFontSizeForFieldKeys(const [
      'ic_id',
      'ic_hts',
      'ic_price_net',
      'ic_price_gross_19',
      'ic_price_wholesale_net',
      'ic_purchase_price_net',
      'ic_source_of_supply',
      'ic_stock',
      'ic_weight',
    ]);

    final compactSize = cataloguePdfCellFontSizeForFieldKeys(const [
      'ic_id',
      'ic_ide',
      'ic_idv',
      'ic_hts',
      'ic_source_of_supply',
      'ic_price_net',
      'ic_price_gross_19',
      'ic_price_wholesale_net',
      'ic_purchase_price_net',
      'ic_stock',
      'ic_weight',
      'ic_description_en_long',
    ]);

    expect(mediumSize, 6.1);
    expect(compactSize, 5.8);
  });
}
