import 'package:arrow_ops/features/item/presentation/item_catalogue_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pdf hard no-wrap Feldzuordnung bleibt stabil', () {
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_id'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_ide'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_idv'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_hts'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_source_of_supply'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_price_net'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_price_gross_19'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_price_wholesale_net'), isTrue);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_purchase_price_net'), isTrue);

    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_idi'), isFalse);
    expect(cataloguePdfHardNoWrapFieldKeys.contains('ic_description_de_long'), isFalse);
  });
}
