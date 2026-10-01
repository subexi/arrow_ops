import '../../customer/domain/customer.dart';
import '../domain/invoice_models.dart';
import '../domain/order_models.dart';

class InvoiceCalculationService {
  const InvoiceCalculationService();

  static const Set<String> _euCountryTokens = {
    'AT', 'AUT', 'AUSTRIA',
    'BE', 'BEL', 'BELGIUM',
    'BG', 'BGR', 'BULGARIA',
    'HR', 'HRV', 'CROATIA',
    'CY', 'CYP', 'CYPRUS',
    'CZ', 'CZE', 'CZECH REPUBLIC',
    'DK', 'DNK', 'DENMARK',
    'EE', 'EST', 'ESTONIA',
    'FI', 'FIN', 'FINLAND',
    'FR', 'FRA', 'FRANCE',
    'DE', 'DEU', 'GERMANY', 'DEUTSCHLAND',
    'GR', 'GRC', 'GREECE',
    'HU', 'HUN', 'HUNGARY',
    'IE', 'IRL', 'IRELAND',
    'IT', 'ITA', 'ITALY',
    'LV', 'LVA', 'LATVIA',
    'LT', 'LTU', 'LITHUANIA',
    'LU', 'LUX', 'LUXEMBOURG',
    'MT', 'MLT', 'MALTA',
    'NL', 'NLD', 'NETHERLANDS',
    'PL', 'POL', 'POLAND',
    'PT', 'PRT', 'PORTUGAL',
    'RO', 'ROU', 'ROMANIA',
    'SK', 'SVK', 'SLOVAKIA',
    'SI', 'SVN', 'SLOVENIA',
    'ES', 'ESP', 'SPAIN',
    'SE', 'SWE', 'SWEDEN',
    'EU',
  };

  InvoiceTotalsData calculateTotals({
    required OrderRow order,
    required List<ItemOrderedRow> items,
    required Customer customer,
  }) {
    final summedItems = items.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalPrice,
    );
    final summedWeight = items.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalWeight,
    );

    final isNoVatCustomer = _isNoVatCustomer(order: order, customer: customer);
    final effectiveVatRate = isNoVatCustomer ? 0.0 : order.oVatRate;
    final normalizedBasis = isNoVatCustomer
        ? 'net'
        : order.oPriceBasis.trim().toLowerCase();

    final double itemsNet;
    final double vatAmount;
    final double itemsGross;

    if (normalizedBasis == 'gross') {
      final divisor = 1 + (effectiveVatRate / 100);
      itemsGross = summedItems;
      itemsNet = divisor <= 0 ? itemsGross : itemsGross / divisor;
      vatAmount = itemsGross - itemsNet;
    } else {
      itemsNet = summedItems;
      vatAmount = effectiveVatRate <= 0 ? 0 : itemsNet * (effectiveVatRate / 100);
      itemsGross = itemsNet + vatAmount;
    }

    final grandTotal = itemsGross + order.oShipping + order.oPaypalFee;

    return InvoiceTotalsData(
      itemsNet: itemsNet,
      vatRate: effectiveVatRate,
      vatAmount: vatAmount,
      itemsGross: itemsGross,
      shipping: order.oShipping,
      paypalFee: order.oPaypalFee,
      grandTotal: grandTotal,
      totalWeightInGram: summedWeight,
    );
  }

  List<InvoiceLineData> buildLines({
    required List<ItemOrderedRow> items,
    required String language,
    bool forceEnglishOnly = false,
  }) {
    final useGerman = language.trim().toUpperCase() == 'DE';

    return items
        .map(
          (item) => InvoiceLineData(
            position: item.ioPos,
            articleId: item.ioItemId,
            articleLabel: item.ioIdi,
            description: _lineDescription(
              item,
              useGerman,
              forceEnglishOnly: forceEnglishOnly,
            ),
            quantity: item.ioQuantity,
            unitPrice: item.ioUnitPrice,
            discountPercent: item.ioDiscount,
            lineTotal: item.ioTotalPrice,
            weightInGram: item.ioTotalWeight,
            hts: item.ioHts,
            color: item.ioColor,
            backorderPending: item.ioBackorderPending != 0,
          ),
        )
        .toList(growable: false);
  }

  String _lineDescription(
    ItemOrderedRow item,
    bool useGerman, {
    required bool forceEnglishOnly,
  }) {
    final externalDesignation = item.ioIde.trim();

    if (forceEnglishOnly) {
      final english = item.ioDescriptionEnLong.trim();
      return _withExternalDesignation(
        baseDescription: english.isEmpty ? '-' : english,
        externalDesignation: externalDesignation,
      );
    }

    final primary = useGerman
        ? item.ioDescriptionDeLong.trim()
        : item.ioDescriptionEnLong.trim();
    if (primary.isNotEmpty) {
      return _withExternalDesignation(
        baseDescription: primary,
        externalDesignation: externalDesignation,
      );
    }

    final fallback = useGerman
        ? item.ioDescriptionEnLong.trim()
        : item.ioDescriptionDeLong.trim();
    if (fallback.isNotEmpty) {
      return _withExternalDesignation(
        baseDescription: fallback,
        externalDesignation: externalDesignation,
      );
    }

    return _withExternalDesignation(
      baseDescription: '-',
      externalDesignation: externalDesignation,
    );
  }

  String _withExternalDesignation({
    required String baseDescription,
    required String externalDesignation,
  }) {
    if (externalDesignation.isEmpty || externalDesignation == '-') {
      return baseDescription;
    }

    if (baseDescription == '-' || baseDescription.trim().isEmpty) {
      return externalDesignation;
    }

    return '$externalDesignation\n$baseDescription';
  }

  bool _isNoVatCustomer({
    required OrderRow order,
    required Customer customer,
  }) {
    if (customer.cVat) {
      return true;
    }
    return _isEuReverseChargeReseller(order: order, customer: customer);
  }

  bool _isEuReverseChargeReseller({
    required OrderRow order,
    required Customer customer,
  }) {
    final isReseller = customer.cDealer || order.oDealer == 1;
    if (!isReseller) {
      return false;
    }

    final vatId = customer.cVatId.trim();
    if (vatId.isEmpty || vatId == '-') {
      return false;
    }

    final countryToken = _normalizedCountryToken(
      customer.cCountryBId,
      fallback: customer.cCountryDId,
    );
    if (countryToken.isEmpty) {
      return false;
    }
    if (countryToken == 'DE' ||
        countryToken == 'DEU' ||
        countryToken == 'GERMANY' ||
        countryToken == 'DEUTSCHLAND') {
      return false;
    }

    return _euCountryTokens.contains(countryToken);
  }

  String _normalizedCountryToken(String? primary, {String? fallback}) {
    String normalize(String? value) => value?.trim().toUpperCase() ?? '';
    final first = normalize(primary);
    if (first.isNotEmpty && first != '-') {
      return first;
    }
    final second = normalize(fallback);
    if (second.isNotEmpty && second != '-') {
      return second;
    }
    return '';
  }
}
