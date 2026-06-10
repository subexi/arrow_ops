import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../order/domain/invoice_models.dart';

class InvoicePdfService {
  const InvoicePdfService();

  // Quick calibration knobs for near-pixel invoice matching.
  static const double _totalsBlockWidth = 244;
  static const double _totalsHeadingIndent = 2;
  static const double _totalsLabelWidth = 130;
  static const double _totalsValueWidth = 96;
  static const double _totalsInnerGap = 8;

  Future<List<int>> generatePdfBytes(InvoiceDocumentData data) async {
    final document = pw.Document();
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final useGerman = data.language.trim().toUpperCase() == 'DE';

    document.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => _buildCompanyFooter(data),
        build: (context) => [
          _buildHeader(data, useGerman),
          pw.SizedBox(height: 10),
          _buildParties(data, useGerman),
          pw.SizedBox(height: 16),
          _buildOrderMetaRow(data, useGerman),
          pw.SizedBox(height: 8),
          _buildInvoiceHeadline(data, useGerman),
          pw.SizedBox(height: 6),
          _buildIntroSection(data, useGerman),
          pw.SizedBox(height: 8),
          _buildLinesTable(data, useGerman),
          pw.SizedBox(height: 10),
          _buildTotalsSection(data, useGerman),
          pw.SizedBox(height: 8),
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
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _singleLineAddress(data.seller),
                style: const pw.TextStyle(fontSize: 7.6, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: _buildPartyBlock(
            useGerman ? 'Absender' : 'Seller',
            data.seller,
            includeContacts: true,
            includeVat: true,
            boxed: false,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildParties(InvoiceDocumentData data, bool useGerman) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _buildPartyBlock(
            useGerman ? 'Kundenadresse' : 'Billing address',
            data.buyer,
            includeContacts: false,
            includeVat: false,
            boxed: false,
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: _buildPartyBlock(
            useGerman ? 'Lieferadresse' : 'Shipping address',
            data.delivery,
            includeContacts: false,
            includeVat: false,
            boxed: false,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildOrderMetaRow(InvoiceDocumentData data, bool useGerman) {
    final leftLabel = useGerman ? 'Ihre Bestellung vom' : 'Your order from';
    final centerLabel = useGerman ? 'Unser Zeichen' : 'Reference';
    final rightLabel = useGerman ? 'Datum' : 'Date';

    return pw.Row(
      children: [
        pw.Expanded(child: _metaCell(leftLabel, data.invoiceDate)),
        pw.SizedBox(width: 20),
        pw.Expanded(child: _metaCell(centerLabel, _initials(data.seller.name))),
        pw.SizedBox(width: 20),
        pw.Expanded(child: _metaCell(rightLabel, data.invoiceDate, alignRight: true)),
      ],
    );
  }

  pw.Widget _metaCell(String label, String value, {bool alignRight = false}) {
    final cross = alignRight ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start;
    return pw.Column(
      crossAxisAlignment: cross,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildInvoiceHeadline(InvoiceDocumentData data, bool useGerman) {
    final label = useGerman ? 'Bestellung / Rechnung-Nr.' : 'Order / Invoice no.';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey500, height: 0.4),
        pw.SizedBox(height: 6),
        pw.Text(
          '$label: ${data.invoiceNumber}',
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildIntroSection(InvoiceDocumentData data, bool useGerman) {
    final gratitude = useGerman
        ? 'Wir danken fuer Ihre Bestellung und berechnen wie folgt:'
        : 'Thank you for your order. We charge as follows:';
    final hasIntraCommunityNote = useGerman &&
        data.totals.vatRate <= 0 &&
        _valid(data.buyer.vatId);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (hasIntraCommunityNote)
          pw.Text(
            'Innergemeinschaftliche Lieferung, Ihre USt.-ID: ${data.buyer.vatId}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        pw.Text(
          gratitude,
          style: pw.TextStyle(fontSize: 9.2, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildPartyBlock(
    String title,
    InvoicePartyData party, {
    bool includeContacts = true,
    bool includeVat = true,
    bool boxed = true,
  }) {
    final lines = <String>[
      if (_valid(party.company)) party.company,
      party.name,
      '${party.street} ${party.houseNumber}'.trim(),
      '${party.postalCode} ${party.city}'.trim(),
      if (_valid(party.countryCode)) party.countryCode,
      if (includeVat && _valid(party.vatId)) 'VAT ID: ${party.vatId}',
      if (includeContacts && _valid(party.email)) party.email,
      if (includeContacts && _valid(party.phone)) party.phone,
    ].where(_valid).toList(growable: false);

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: boxed
          ? pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
            )
          : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2),
          ),
          pw.SizedBox(height: 3),
          ...lines.map(
            (line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9.6, lineSpacing: 1.15)),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildLinesTable(InvoiceDocumentData data, bool useGerman) {
    final headers = [
      useGerman ? 'Pos' : 'Pos.',
      useGerman ? 'Artikel' : 'ID',
      useGerman ? 'Bezeichnung' : 'Description',
      useGerman ? 'Menge' : 'Qty',
      useGerman ? 'Einzelpreis' : 'Unit price',
      useGerman ? 'Rabatt %' : 'Discount %',
      useGerman ? 'Gesamtpreis' : 'Total',
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

    const accentRed = PdfColor(0.82, 0.18, 0.16);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(),
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder(
        top: const pw.BorderSide(color: accentRed, width: 0.9),
        bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.4),
        horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
        verticalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
      ),
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
    final vatHint = useGerman
      ? '${totals.vatRate.toStringAsFixed(0)}% MwSt. im Warenwert enthalten'
        : 'VAT (${totals.vatRate.toStringAsFixed(0)}%) included in goods value';

    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                totals.vatRate <= 0 ? '' : vatHint,
                style: const pw.TextStyle(fontSize: 8.6, color: PdfColors.grey700),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: _totalsBlockWidth,
              child: pw.Column(
                children: [
                  if (useGerman) ...[
                    _totalsHeadingRow('Summe'),
                    _totalsRow(
                      'Warenwert',
                      _formatMoney(_displayGoodsValue(data), data.currency, true),
                    ),
                    _totalsRow(
                      'Versand',
                      _formatMoney(totals.shipping, data.currency, true),
                    ),
                    _totalsRow(
                      'SWa PayPal',
                      _formatMoney(totals.paypalFee, data.currency, true),
                    ),
                    pw.Divider(color: PdfColors.grey600, height: 0.4),
                    _totalsRow(
                      'Endbetrag',
                      _formatMoney(totals.grandTotal, data.currency, true),
                      bold: true,
                    ),
                  ] else ...[
                    _totalsRow(
                      'Goods net',
                      _formatMoney(totals.itemsNet, data.currency, false),
                    ),
                    _totalsRow(
                      'VAT (${totals.vatRate.toStringAsFixed(1)}%)',
                      _formatMoney(totals.vatAmount, data.currency, false),
                    ),
                    _totalsRow(
                      'Goods gross',
                      _formatMoney(totals.itemsGross, data.currency, false),
                    ),
                    _totalsRow(
                      'Shipping',
                      _formatMoney(totals.shipping, data.currency, false),
                    ),
                    _totalsRow(
                      'PayPal fee',
                      _formatMoney(totals.paypalFee, data.currency, false),
                    ),
                    pw.Divider(color: PdfColors.grey600, height: 0.4),
                    _totalsRow(
                      'Grand total',
                      _formatMoney(totals.grandTotal, data.currency, false),
                      bold: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _totalsHeadingRow(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: _totalsHeadingIndent, bottom: 1),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8.8, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  double _displayGoodsValue(InvoiceDocumentData data) {
    final basis = data.priceBasis.trim().toLowerCase();
    if (basis == 'gross') {
      return data.totals.itemsGross;
    }
    return data.totals.itemsNet;
  }

  pw.Widget _totalsRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 10 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: _totalsLabelWidth,
            child: pw.Text(label, style: style),
          ),
          pw.SizedBox(width: _totalsInnerGap),
          pw.SizedBox(
            width: _totalsValueWidth,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(value, style: style),
            ),
          ),
        ],
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
        pw.Divider(color: PdfColors.grey500, height: 0.3),
        pw.SizedBox(height: 4),
        if (_valid(data.note)) pw.Text('$noteTitle: ${data.note}', style: const pw.TextStyle(fontSize: 9)),
        if (_valid(data.paymentLabel))
          pw.Text('$paymentTitle: ${data.paymentLabel}', style: const pw.TextStyle(fontSize: 9)),
        if (_valid(data.payDate))
          pw.Text('$payDateTitle: ${data.payDate}', style: const pw.TextStyle(fontSize: 9)),
        if (_valid(data.deliveryDate))
          pw.Text('$deliveryTitle: ${data.deliveryDate}', style: const pw.TextStyle(fontSize: 9)),
        if (_valid(data.trackingCode))
          pw.Text('$trackingTitle: ${data.trackingCode}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(
          '${useGerman ? 'Gewicht gesamt' : 'Total weight'}: ${_formatWeight(data.totals.totalWeightInGram, useGerman)}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  pw.Widget _buildCompanyFooter(InvoiceDocumentData data) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _footerColumn(data.footer.leftLines)),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _footerColumn(data.footer.centerLines)),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _footerColumn(data.footer.rightLines)),
        ],
      ),
    );
  }

  pw.Widget _footerColumn(List<String> lines) {
    if (lines.isEmpty) {
      return pw.SizedBox();
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1.2),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 7.8, lineSpacing: 1.1)),
            ),
          )
          .toList(growable: false),
    );
  }

  String _singleLineAddress(InvoicePartyData party) {
    final parts = <String>[
      if (_valid(party.company)) party.company,
      if (_valid(party.street)) '${party.street} ${party.houseNumber}'.trim(),
      if (_valid(party.postalCode) || _valid(party.city)) '${party.postalCode} ${party.city}'.trim(),
      if (_valid(party.countryCode)) party.countryCode,
    ];
    return parts.join(' • ');
  }

  String _initials(String source) {
    final parts = source.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) {
      return '-';
    }
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
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
