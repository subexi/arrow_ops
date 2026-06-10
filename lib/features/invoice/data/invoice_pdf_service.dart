import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../order/domain/invoice_models.dart';

class InvoicePdfService {
  const InvoicePdfService();

  Future<List<int>> generatePdfBytes(InvoiceDocumentData data) async {
    final document = pw.Document();
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final useGerman = data.language.trim().toUpperCase() == 'DE';

    document.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _buildHeader(data, useGerman),
          pw.SizedBox(height: 14),
          _buildParties(data, useGerman),
          pw.SizedBox(height: 14),
          _buildLinesTable(data, useGerman),
          pw.SizedBox(height: 14),
          _buildTotalsSection(data, useGerman),
          pw.SizedBox(height: 10),
          _buildMetaSection(data, useGerman),
        ],
      ),
    );

    return document.save();
  }

  Future<String> savePdfToDocuments({
    required List<int> pdfBytes,
    required String fileName,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetPath = p.join(docsDir.path, fileName);
    await File(targetPath).writeAsBytes(pdfBytes);
    return targetPath;
  }

  String buildDefaultFileName(InvoiceDocumentData data) {
    final cleanNumber = data.invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'invoice_$cleanNumber.pdf';
  }

  pw.Widget _buildHeader(InvoiceDocumentData data, bool useGerman) {
    final title = useGerman ? 'Rechnung' : 'Invoice';
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('${useGerman ? 'Rechnungsnr.' : 'Invoice no.'}: ${data.invoiceNumber}'),
            pw.Text('${useGerman ? 'Rechnungsdatum' : 'Invoice date'}: ${data.invoiceDate}'),
            pw.Text('${useGerman ? 'Auftrag' : 'Order'}: ${data.orderId}'),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildParties(InvoiceDocumentData data, bool useGerman) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _buildPartyBlock(useGerman ? 'Verkaeufer' : 'Seller', data.seller)),
        pw.SizedBox(width: 24),
        pw.Expanded(child: _buildPartyBlock(useGerman ? 'Kaeufer' : 'Buyer', data.buyer)),
      ],
    );
  }

  pw.Widget _buildPartyBlock(String title, InvoicePartyData party) {
    final lines = <String>[
      party.name,
      if (_valid(party.company)) party.company,
      '${party.street} ${party.houseNumber}'.trim(),
      '${party.postalCode} ${party.city}'.trim(),
      if (_valid(party.countryCode)) party.countryCode,
      if (_valid(party.vatId)) 'VAT ID: ${party.vatId}',
      if (_valid(party.email)) party.email,
      if (_valid(party.phone)) party.phone,
    ].where(_valid).toList(growable: false);

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          ...lines.map(pw.Text.new),
        ],
      ),
    );
  }

  pw.Widget _buildLinesTable(InvoiceDocumentData data, bool useGerman) {
    final headers = [
      useGerman ? 'Pos.' : 'Pos.',
      'ID',
      useGerman ? 'Bezeichnung' : 'Description',
      useGerman ? 'Menge' : 'Qty',
      useGerman ? 'Einzelpreis' : 'Unit price',
      useGerman ? 'Rabatt %' : 'Discount %',
      useGerman ? 'Gesamt' : 'Total',
    ];

    final rows = data.lines
        .map(
          (line) => [
            line.position.toString(),
            line.articleLabel,
            line.description,
            line.quantity.toString(),
            _formatMoney(line.unitPrice, data.currency, useGerman),
            line.discountPercent.toStringAsFixed(1),
            _formatMoney(line.lineTotal, data.currency, useGerman),
          ],
        )
        .toList(growable: false);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.all(4),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FixedColumnWidth(65),
        3: const pw.FixedColumnWidth(32),
        4: const pw.FixedColumnWidth(62),
        5: const pw.FixedColumnWidth(45),
        6: const pw.FixedColumnWidth(62),
      },
    );
  }

  pw.Widget _buildTotalsSection(InvoiceDocumentData data, bool useGerman) {
    final totals = data.totals;
    final rows = <List<String>>[
      [useGerman ? 'Warenwert netto' : 'Goods net', _formatMoney(totals.itemsNet, data.currency, useGerman)],
      [
        '${useGerman ? 'MwSt' : 'VAT'} (${totals.vatRate.toStringAsFixed(1)}%)',
        _formatMoney(totals.vatAmount, data.currency, useGerman),
      ],
      [useGerman ? 'Warenwert brutto' : 'Goods gross', _formatMoney(totals.itemsGross, data.currency, useGerman)],
      [useGerman ? 'Versand' : 'Shipping', _formatMoney(totals.shipping, data.currency, useGerman)],
      [useGerman ? 'PayPal-Gebuehr' : 'PayPal fee', _formatMoney(totals.paypalFee, data.currency, useGerman)],
      [
        useGerman ? 'Gesamtbetrag' : 'Grand total',
        _formatMoney(totals.grandTotal, data.currency, useGerman),
      ],
    ];

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 260,
        child: pw.TableHelper.fromTextArray(
          data: rows,
          headerCount: 0,
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          border: pw.TableBorder.all(color: PdfColors.grey500),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
          },
        ),
      ),
    );
  }

  pw.Widget _buildMetaSection(InvoiceDocumentData data, bool useGerman) {
    final noteTitle = useGerman ? 'Hinweis' : 'Note';
    final paymentTitle = useGerman ? 'Zahlung' : 'Payment';
    final payDateTitle = useGerman ? 'Zahldatum' : 'Pay date';
    final deliveryTitle = useGerman ? 'Lieferdatum' : 'Delivery date';
    final trackingTitle = useGerman ? 'Tracking' : 'Tracking';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (_valid(data.note)) pw.Text('$noteTitle: ${data.note}'),
        if (_valid(data.paymentLabel)) pw.Text('$paymentTitle: ${data.paymentLabel}'),
        if (_valid(data.payDate)) pw.Text('$payDateTitle: ${data.payDate}'),
        if (_valid(data.deliveryDate)) pw.Text('$deliveryTitle: ${data.deliveryDate}'),
        if (_valid(data.trackingCode)) pw.Text('$trackingTitle: ${data.trackingCode}'),
        pw.SizedBox(height: 6),
        pw.Text(
          '${useGerman ? 'Gewicht gesamt' : 'Total weight'}: ${_formatWeight(data.totals.totalWeightInGram, useGerman)}',
        ),
      ],
    );
  }

  String _formatMoney(double value, String currency, bool useGerman) {
    final fixed = value.toStringAsFixed(2);
    final number = useGerman ? fixed.replaceAll('.', ',') : fixed;
    return '$number $currency';
  }

  String _formatWeight(double gram, bool useGerman) {
    final fixed = gram.toStringAsFixed(1);
    return useGerman ? '${fixed.replaceAll('.', ',')} g' : '$fixed g';
  }

  bool _valid(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isNotEmpty && normalized != '-';
  }
}
