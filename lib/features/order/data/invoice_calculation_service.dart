import '../../customer/domain/customer.dart';
import '../domain/invoice_models.dart';
import '../domain/order_models.dart';

class InvoiceCalculationService {
  const InvoiceCalculationService();

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

    final isNoVatCustomer = customer.cVat;
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
          ),
        )
        .toList(growable: false);
  }

  String _lineDescription(
    ItemOrderedRow item,
    bool useGerman, {
    required bool forceEnglishOnly,
  }) {
    if (forceEnglishOnly) {
      final english = item.ioDescriptionEnLong.trim();
      return english.isEmpty ? '-' : english;
    }

    final primary = useGerman
        ? item.ioDescriptionDeLong.trim()
        : item.ioDescriptionEnLong.trim();
    if (primary.isNotEmpty) {
      return primary;
    }

    final fallback = useGerman
        ? item.ioDescriptionEnLong.trim()
        : item.ioDescriptionDeLong.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }

    return '-';
  }
}
