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

  group('InvoicePdfService.debugBuildLineHeaders', () {
    const service = InvoicePdfService();

    test('uses legacy DE headers for reseller invoice with VAT-ID', () {
      final data = _documentData(
        language: 'DE',
        isReseller: true,
        isNoVatCustomer: true,
        buyerVatId: 'DE123456789',
      );

      final headers = service.debugBuildLineHeaders(
        data: data,
        useGerman: true,
        showDiscountColumn: false,
      );

      expect(headers.contains('Einzelpreis'), isTrue);
      expect(headers.contains('Gesamtpreis'), isTrue);
      expect(headers.contains('Einzelpreis netto'), isFalse);
      expect(headers.contains('Gesamtpreis netto'), isFalse);
    });

    test('keeps DE netto headers for non-reseller net invoice', () {
      final data = _documentData(
        language: 'DE',
        isReseller: false,
        isNoVatCustomer: true,
        buyerVatId: 'DE123456789',
      );

      final headers = service.debugBuildLineHeaders(
        data: data,
        useGerman: true,
        showDiscountColumn: false,
      );

      expect(headers.contains('Einzelpreis'), isTrue);
      expect(headers.contains('Gesamtpreis'), isTrue);
      expect(headers.contains('Einzelpreis netto'), isFalse);
      expect(headers.contains('Gesamtpreis netto'), isFalse);
    });
  });

  group('InvoicePdfService.buildDefaultFileName', () {
    const service = InvoicePdfService();

    test('strips special characters from last name token', () {
      final data = _documentData(lastName: 'Muller/Jager-Muller-Muller');

      final fileName = service.buildDefaultFileName(data);

      expect(fileName, equals('1001_Muller_Jager-Muller-Muller_in.pdf'));
    });

    test('falls back to Unbekannt when last name has no usable token', () {
      final data = _documentData(lastName: '***');

      final fileName = service.buildDefaultFileName(data);

      expect(fileName, equals('1001_Unbekannt_in.pdf'));
    });

    test(
      'adds end-customer last name for packing list when delivery differs',
      () {
        final data = _documentData(
          kind: InvoiceDocumentKind.packingList,
          lastName: 'Mueller',
          delivery: const InvoicePartyData(
            name: 'Anna Schmidt',
            street: 'Lieferweg',
            houseNumber: '7',
            postalCode: '12345',
            city: 'Berlin',
            countryCode: 'DE',
          ),
        );

        final fileName = service.buildDefaultFileName(data);

        expect(fileName, equals('1001_Mueller_Schmidt_pl.pdf'));
      },
    );

    test(
      'keeps previous packing list filename when delivery equals billing',
      () {
        const sameParty = InvoicePartyData(
          name: 'Buyer',
          lastName: 'Mueller',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        );
        final data = _documentData(
          kind: InvoiceDocumentKind.packingList,
          lastName: 'Mueller',
          buyer: sameParty,
          delivery: sameParty,
        );

        final fileName = service.buildDefaultFileName(data);

        expect(fileName, equals('1001_Mueller_pl.pdf'));
      },
    );

    test(
      'does not append end-customer token when only recipient name differs',
      () {
        final data = _documentData(
          kind: InvoiceDocumentKind.packingList,
          lastName: 'Mueller',
          buyer: const InvoicePartyData(
            name: 'Buyer Name',
            lastName: 'Mueller',
            company: 'Arrow GmbH',
            street: 'Main Street',
            houseNumber: '1',
            postalCode: '11111',
            city: 'Stuttgart',
            countryCode: 'DE',
          ),
          delivery: const InvoicePartyData(
            name: 'Endkunde Name',
            street: 'Main Street',
            houseNumber: '1',
            postalCode: '11111',
            city: 'Stuttgart',
            countryCode: 'DE',
          ),
        );

        final fileName = service.buildDefaultFileName(data);

        expect(fileName, equals('1001_Mueller_pl.pdf'));
      },
    );
  });

  group('InvoicePdfService delivery address rubric visibility', () {
    const service = InvoicePdfService();

    test('shows rubric for packing list when delivery differs', () {
      final data = _documentData(
        kind: InvoiceDocumentKind.packingList,
        buyer: const InvoicePartyData(
          name: 'Buyer',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        ),
        delivery: const InvoicePartyData(
          name: 'Delivery',
          street: 'Lieferweg',
          houseNumber: '7',
          postalCode: '12345',
          city: 'Berlin',
          countryCode: 'DE',
        ),
      );

      expect(service.debugShouldShowDeliveryAddressRubric(data), isTrue);
    });

    test('hides rubric for packing list when delivery equals billing', () {
      const sameAddress = InvoicePartyData(
        name: 'Buyer',
        street: 'Main Street',
        houseNumber: '1',
        postalCode: '11111',
        city: 'Stuttgart',
        countryCode: 'DE',
      );
      final data = _documentData(
        kind: InvoiceDocumentKind.packingList,
        buyer: sameAddress,
        delivery: sameAddress,
      );

      expect(service.debugShouldShowDeliveryAddressRubric(data), isFalse);
    });

    test('hides rubric when only recipient name differs', () {
      final data = _documentData(
        kind: InvoiceDocumentKind.packingList,
        buyer: const InvoicePartyData(
          name: 'Buyer Name',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        ),
        delivery: const InvoicePartyData(
          name: 'Endkunde Name',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        ),
      );

      expect(service.debugShouldShowDeliveryAddressRubric(data), isFalse);
    });

    test('uses buyer address block for packing list when addresses are equal', () {
      const buyer = InvoicePartyData(
        name: 'Buyer Name',
        company: 'Arrow GmbH',
        street: 'Main Street',
        houseNumber: '1',
        postalCode: '11111',
        city: 'Stuttgart',
        countryCode: 'DE',
      );
      const delivery = InvoicePartyData(
        name: 'Endkunde Name',
        street: 'Main Street',
        houseNumber: '1',
        postalCode: '11111',
        city: 'Stuttgart',
        countryCode: 'DE',
      );
      final data = _documentData(
        kind: InvoiceDocumentKind.packingList,
        buyer: buyer,
        delivery: delivery,
      );

      expect(service.debugUsesBuyerForShippingRubric(data), isTrue);
    });

    test('uses delivery address block for packing list when addresses differ', () {
      final data = _documentData(
        kind: InvoiceDocumentKind.packingList,
        buyer: const InvoicePartyData(
          name: 'Buyer Name',
          company: 'Arrow GmbH',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        ),
        delivery: const InvoicePartyData(
          name: 'Endkunde Name',
          street: 'Lieferweg',
          houseNumber: '7',
          postalCode: '12345',
          city: 'Berlin',
          countryCode: 'DE',
        ),
      );

      expect(service.debugUsesBuyerForShippingRubric(data), isFalse);
    });

    test('uses buyer address block for invoice when addresses are equal', () {
      const buyer = InvoicePartyData(
        name: 'Buyer Name',
        company: 'Arrow GmbH',
        street: 'Main Street',
        houseNumber: '1',
        postalCode: '11111',
        city: 'Stuttgart',
        countryCode: 'DE',
      );
      const delivery = InvoicePartyData(
        name: 'Endkunde Name',
        street: 'Main Street',
        houseNumber: '1',
        postalCode: '11111',
        city: 'Stuttgart',
        countryCode: 'DE',
      );
      final data = _documentData(
        kind: InvoiceDocumentKind.invoice,
        buyer: buyer,
        delivery: delivery,
      );

      expect(service.debugUsesBuyerForShippingRubric(data), isTrue);
    });

    test('uses delivery address block for invoice when addresses differ', () {
      final data = _documentData(
        kind: InvoiceDocumentKind.invoice,
        buyer: const InvoicePartyData(
          name: 'Buyer Name',
          company: 'Arrow GmbH',
          street: 'Main Street',
          houseNumber: '1',
          postalCode: '11111',
          city: 'Stuttgart',
          countryCode: 'DE',
        ),
        delivery: const InvoicePartyData(
          name: 'Endkunde Name',
          street: 'Lieferweg',
          houseNumber: '7',
          postalCode: '12345',
          city: 'Berlin',
          countryCode: 'DE',
        ),
      );

      expect(service.debugUsesBuyerForShippingRubric(data), isFalse);
    });
  });

  group('InvoicePdfService.debugSanitizePdfText', () {
    const service = InvoicePdfService();

    test('converts escaped newline sequences to real line breaks when enabled', () {
      final text = service.debugSanitizePdfText(
        'Zeile 1\\nZeile 2',
        preserveLineBreaks: true,
      );

      expect(text, equals('Zeile 1\nZeile 2'));
    });

    test('flattens line breaks to spaces in normal text mode', () {
      final text = service.debugSanitizePdfText('Zeile 1\\nZeile 2');

      expect(text, equals('Zeile 1 Zeile 2'));
    });

    test('converts visible return symbols to real line breaks', () {
      final text = service.debugSanitizePdfText(
        'Zeile 1↵Zeile 2⏎Zeile 3',
        preserveLineBreaks: true,
      );

      expect(text, equals('Zeile 1\nZeile 2\nZeile 3'));
    });

    test('keeps bullet character instead of replacing it with star', () {
      final text = service.debugSanitizePdfText('• Punkt A');

      expect(text, equals('• Punkt A'));
    });
  });
}

InvoiceDocumentData _documentData({
  String language = 'EN',
  bool isReseller = false,
  bool isNoVatCustomer = false,
  String buyerVatId = '-',
  String lastName = 'BuyerLastName',
  InvoiceDocumentKind kind = InvoiceDocumentKind.invoice,
  InvoicePartyData? buyer,
  InvoicePartyData? delivery,
}) {
  final effectiveBuyer =
      buyer ??
      InvoicePartyData(
        name: 'Buyer',
        lastName: lastName,
        vatId: buyerVatId,
      );

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
    buyer: effectiveBuyer,
    delivery: delivery ?? const InvoicePartyData(name: 'Delivery'),
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
