import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arrow_ops/features/invoice/data/invoice_pdf_service.dart';
import 'package:arrow_ops/features/order/domain/invoice_models.dart';

void main() {
  test('generate example invoice PDF', () async {
    final pdfService = InvoicePdfService();

    final seller = InvoicePartyData(
      name: 'Arrow Engineering',
      lastName: 'Engineering',
      company: 'Arrow-Engineering UG',
      street: 'Musterstrasse',
      houseNumber: '1',
      postalCode: '10115',
      city: 'Berlin',
      countryCode: 'DE',
      email: 'sales@example.com',
    );

    final buyer = InvoicePartyData(
      name: 'Max Mustermann',
      lastName: 'Mustermann',
      company: '-',
      street: 'Hauptstrasse',
      houseNumber: '7',
      postalCode: '8000',
      city: 'Zürich',
      countryCode: 'CH',
      email: 'max@example.com',
    );

    final delivery = InvoicePartyData(
      name: 'Anna Beispiel',
      lastName: 'Beispiel',
      company: '-',
      street: 'Andere Strasse',
      houseNumber: '9',
      postalCode: '8001',
      city: 'Zürich',
      countryCode: 'CH',
      email: 'anna@example.com',
    );

    final totals = InvoiceTotalsData(
      itemsNet: 100.0,
      vatRate: 7.7,
      vatAmount: 7.7,
      itemsGross: 107.7,
      shipping: 5.0,
      paypalFee: 1.0,
      grandTotal: 113.7,
      totalWeightInGram: 1200.0,
    );

    final lines = [
      InvoiceLineData(
        position: 1,
        articleId: 123,
        articleLabel: 'Widget',
        description: 'Ein Beispielartikel',
        quantity: 1,
        unitPrice: 100.0,
        discountPercent: 0.0,
        lineTotal: 100.0,
        weightInGram: 1200.0,
      ),
    ];

    final data = InvoiceDocumentData(
      documentKind: InvoiceDocumentKind.invoice,
      isProforma: false,
      invoiceNumber: 'INV-2026-001',
      invoiceDate: '2026-08-25',
      orderDate: '2026-08-24',
      orderId: 'ORD-100',
      currency: 'CHF',
      language: 'DE',
      priceBasis: 'gross',
      isReseller: false,
      isNoVatCustomer: false,
      seller: seller,
      buyer: buyer,
      delivery: delivery,
      footer: InvoiceFooterData(leftLines: [], centerLines: [], rightLines: []),
      lines: lines,
      totals: totals,
      note: 'Danke fuer Ihren Einkauf',
    );

    final bytes = await pdfService.generatePdfBytes(data);
    final out = File('example_generated_invoice.pdf');
    await out.writeAsBytes(bytes, flush: true);
    // Verify the file was written and clean up afterwards.
    expect(await out.exists(), isTrue);
    try {
      await out.delete();
    } catch (_) {}
  }, timeout: Timeout(Duration(seconds: 30)));
}
