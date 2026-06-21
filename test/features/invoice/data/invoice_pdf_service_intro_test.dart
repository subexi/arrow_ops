import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_ops/features/invoice/data/invoice_pdf_service.dart';
import 'package:arrow_ops/features/order/domain/invoice_models.dart';

void main() {
  group('InvoicePdfService.debugBuildIntroLines', () {
    const service = InvoicePdfService();

    test('adds bold EN taxfree line above gratitude for reseller no-vat customer', () {
      final data = _documentData(
        language: 'EN',
        isReseller: true,
        isNoVatCustomer: true,
        buyerVatId: 'DE123456789',
      );

      final lines = service.debugBuildIntroLines(data, false);

      expect(lines, hasLength(2));
      expect(lines[0].text, 'Taxfree intra-Community delivery VAT#: DE123456789');
      expect(lines[0].bold, isTrue);
      expect(lines[1].text, 'Thank you for your order. We charge as follows:');
      expect(lines[1].bold, isTrue);
    });

    test('does not add EN taxfree line when VAT-ID is missing', () {
      final data = _documentData(
        language: 'EN',
        isReseller: true,
        isNoVatCustomer: true,
        buyerVatId: '-',
      );

      final lines = service.debugBuildIntroLines(data, false);

      expect(lines, hasLength(1));
      expect(lines.single.text, 'Thank you for your order. We charge as follows:');
    });

    test('does not add EN taxfree line for packing list', () {
      final data = _documentData(
        language: 'EN',
        isReseller: true,
        isNoVatCustomer: true,
        buyerVatId: 'DE123456789',
        kind: InvoiceDocumentKind.packingList,
      );

      final lines = service.debugBuildIntroLines(data, false);

      expect(lines, isEmpty);
    });

    test('adds DE intra-community note before gratitude when VAT is zero', () {
      final data = _documentData(
        language: 'DE',
        isReseller: false,
        isNoVatCustomer: true,
        buyerVatId: 'DE123456789',
      );

      final lines = service.debugBuildIntroLines(data, true);

      expect(lines, hasLength(2));
      expect(
        lines[0].text,
        'Innergemeinschaftliche Lieferung, Ihre USt.-ID: DE123456789',
      );
      expect(lines[0].bold, isFalse);
      expect(lines[1].text, 'Wir danken für Ihre Bestellung und berechnen wie folgt:');
      expect(lines[1].bold, isTrue);
    });
  });
}

InvoiceDocumentData _documentData({
  String language = 'EN',
  bool isReseller = false,
  bool isNoVatCustomer = false,
  String buyerVatId = '-',
  InvoiceDocumentKind kind = InvoiceDocumentKind.invoice,
}) {
  return InvoiceDocumentData(
    documentKind: kind,
    invoiceNumber: 'INV-1',
    invoiceDate: '2026-06-20',
    orderDate: '2026-06-19',
    orderId: '1001',
    currency: 'EUR',
    language: language,
    priceBasis: 'net',
    isReseller: isReseller,
    isNoVatCustomer: isNoVatCustomer,
    seller: const InvoicePartyData(name: 'Seller'),
    buyer: InvoicePartyData(name: 'Buyer', vatId: buyerVatId),
    delivery: const InvoicePartyData(name: 'Delivery'),
    footer: const InvoiceFooterData(),
    lines: const <InvoiceLineData>[],
    totals: const InvoiceTotalsData(
      itemsNet: 100,
      vatRate: 0,
      vatAmount: 0,
      itemsGross: 100,
      shipping: 0,
      paypalFee: 0,
      grandTotal: 100,
      totalWeightInGram: 0,
    ),
  );
}
