import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../order/domain/invoice_models.dart';

class InvoicePdfService {
  const InvoicePdfService();

  // Quick calibration knobs for near-pixel invoice matching.
  static const String _logoAssetPath = 'lib/images/af_schrift_plus_heartbeat.png';
  static const double _logoWidth = 188;
  static const double _rightAlignedBlockWidth = _logoWidth;
  static const double _logoSpacingToSender = 4;
  static const double _senderTopOffset = 1;
  static const double _windowAddressTopOffset = 86;
  static const double _addressColumnsGap = 20;
  static const double _totalsBlockWidth = 244;
  static const double _totalsLabelWidth = 130;
  static const double _totalsInnerGap = 8;
  static const double _totalsValueRightInset = 4;

  Future<List<int>> generatePdfBytes(InvoiceDocumentData data) async {
    final document = pw.Document();
    final baseFont = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final useGerman = data.language.trim().toUpperCase() == 'DE';
    final logoImage = await _loadLogoImage();

    document.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => _buildCompanyFooter(data),
        build: (context) => [
          _buildHeader(data, useGerman, logoImage),
          pw.SizedBox(height: 0),
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
    final numberToken = _normalizedNumberToken(data.orderId, data.invoiceNumber);
    final lastNameToken = _normalizedLastNameToken(data.buyer.name);
    return '${numberToken}_${lastNameToken}_in.pdf';
  }

  String _normalizedNumberToken(String orderId, String invoiceNumber) {
    final orderDigits = orderId.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (orderDigits.isNotEmpty) {
      return orderDigits;
    }

    final invoiceDigits = invoiceNumber.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (invoiceDigits.isNotEmpty) {
      return invoiceDigits;
    }

    return '0000000000';
  }

  String _normalizedLastNameToken(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty && part != '-')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'Unbekannt';
    }

    final lastName = parts.last.replaceAll(RegExp(r'[^A-Za-z0-9ÄÖÜäöüß_-]'), '');
    if (lastName.isEmpty) {
      return 'Unbekannt';
    }
    return lastName;
  }

  Future<pw.MemoryImage?> _loadLogoImage() async {
    try {
      final data = await rootBundle.load(_logoAssetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) {
        return null;
      }
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  pw.Widget _buildHeader(
    InvoiceDocumentData data,
    bool useGerman,
    pw.MemoryImage? logoImage,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: _windowAddressTopOffset),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _singleLineAddress(data.seller),
                  style: const pw.TextStyle(fontSize: 7.6, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 1),
                _buildPartyBlock(
                  '',
                  data.buyer,
                  includeContacts: false,
                  includeVat: false,
                  boxed: false,
                  bodyFontSize: 10.8,
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 20),
        pw.SizedBox(
          width: _rightAlignedBlockWidth,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImage != null) ...[
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Image(
                    logoImage,
                    width: _logoWidth,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(height: _logoSpacingToSender),
              ],
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: _senderTopOffset),
                child: _buildPartyBlock(
                  '',
                  data.seller,
                  includeContacts: true,
                  includeVat: true,
                  boxed: false,
                  addGermanStreetCityGap: false,
                  showGermanyCountry: true,
                  addCountryGap: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildParties(InvoiceDocumentData data, bool useGerman) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.SizedBox()),
        pw.SizedBox(width: _addressColumnsGap),
        pw.SizedBox(
          width: _rightAlignedBlockWidth,
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
    const referenceInitials = 'HD';

    return pw.Row(
      children: [
        pw.Expanded(child: _metaCell(leftLabel, data.invoiceDate)),
        pw.SizedBox(width: 20),
        pw.Expanded(child: _metaCell(centerLabel, referenceInitials)),
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
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey700,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildInvoiceHeadline(InvoiceDocumentData data, bool useGerman) {
    final label = useGerman ? 'Bestellung / Rechnung-Nr.' : 'Order / Invoice no.';
    final documentNumber = data.orderId.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey500, height: 0.4),
        pw.SizedBox(height: 6),
        pw.Text(
          '$label: $documentNumber',
          style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildIntroSection(InvoiceDocumentData data, bool useGerman) {
    final gratitude = useGerman
        ? 'Wir danken für Ihre Bestellung und berechnen wie folgt:'
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
          style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold),
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
    double bodyFontSize = 9.6,
    bool addGermanStreetCityGap = true,
    bool showGermanyCountry = false,
    bool addCountryGap = true,
  }) {
    final countryLine = _displayCountryForAddress(
      party.countryCode,
      showGermany: showGermanyCountry,
    );
    final isGermany = _isGermanAddress(party.countryCode);
    final widgets = <pw.Widget>[
      if (_valid(party.company)) _partyLine(party.company, fontSize: bodyFontSize),
      if (_valid(party.name)) _partyLine(party.name, fontSize: bodyFontSize),
      if (_valid(_joinValid([party.street, party.houseNumber])))
        _partyLine(_joinValid([party.street, party.houseNumber]), fontSize: bodyFontSize),
      if (addGermanStreetCityGap && isGermany && _valid(_joinValid([party.postalCode, party.city])))
        pw.SizedBox(height: 10),
      if (_valid(_joinValid([party.postalCode, party.city])))
        _partyLine(_joinValid([party.postalCode, party.city]), fontSize: bodyFontSize),
      if (addCountryGap && _valid(countryLine)) pw.SizedBox(height: 10),
      if (_valid(countryLine)) _partyLine(countryLine, fontSize: bodyFontSize),
      if (includeVat && _valid(party.vatId))
        _partyLine('VAT ID: ${party.vatId}', fontSize: bodyFontSize),
      if (includeContacts && _valid(party.phone))
        _partyLine('Phone: ${party.phone.trim()}', fontSize: bodyFontSize),
      if (includeContacts && _valid(party.email))
        _partyLabeledLinkLine(
          label: 'email: ',
          linkText: party.email.trim(),
          url: 'mailto:${party.email.trim()}',
          fontSize: bodyFontSize,
        ),
      if (includeContacts && _valid(party.web))
        _partyLabeledLinkLine(
          label: 'web: ',
          linkText: party.web.trim(),
          url: _normalizeWebUrl(party.web),
          fontSize: bodyFontSize,
        ),
    ];

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
          if (_valid(title)) ...[
            pw.Text(
              title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.2),
            ),
            pw.SizedBox(height: 3),
          ],
          ...widgets,
        ],
      ),
    );
  }

  pw.Widget _partyLine(String text, {double fontSize = 9.6}) {
    return pw.Text(text, style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1.15));
  }

  pw.Widget _partyLabeledLinkLine({
    required String label,
    required String linkText,
    required String url,
    double fontSize = 9.6,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1.15)),
        pw.UrlLink(
          destination: url,
          child: pw.Text(
            linkText,
            style: pw.TextStyle(
              fontSize: fontSize,
              lineSpacing: 1.15,
              color: PdfColors.blue700,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildLinesTable(InvoiceDocumentData data, bool useGerman) {
    final showDiscountColumn = data.lines.any((line) => line.discountPercent.abs() > 0.0001);
    final headers = <String>[
      useGerman ? 'Pos' : 'Pos.',
      useGerman ? 'Artikel' : 'ID',
      useGerman ? 'Bezeichnung' : 'Description',
      useGerman ? 'Menge' : 'Qty',
      useGerman ? 'Einzelpreis' : 'Unit price',
      if (showDiscountColumn) useGerman ? 'Rabatt %' : 'Discount %',
      useGerman ? 'Gesamtpreis' : 'Total',
    ];

    final rows = data.lines.map((line) {
      return <String>[
        line.position.toString(),
        line.articleLabel,
        line.description,
        line.quantity.toString(),
        _formatMoney(line.unitPrice, data.currency, useGerman),
        if (showDiscountColumn) line.discountPercent.toStringAsFixed(1),
        _formatMoney(line.lineTotal, data.currency, useGerman),
      ];
    }).toList(growable: false);

    const accentRed = PdfColor(0.82, 0.18, 0.16);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: const pw.BoxDecoration(),
      headerStyle: pw.TextStyle(fontSize: 7.6, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: <int, pw.Alignment>{
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        if (showDiscountColumn) 5: pw.Alignment.center,
        showDiscountColumn ? 6 : 5: pw.Alignment.centerRight,
      },
      border: pw.TableBorder(
        top: const pw.BorderSide(color: accentRed, width: 0.9),
        bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.4),
        horizontalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
        verticalInside: const pw.BorderSide(color: PdfColors.grey300, width: 0.3),
      ),
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(30),
        1: const pw.FixedColumnWidth(65),
        3: const pw.FixedColumnWidth(32),
        4: const pw.FixedColumnWidth(62),
        if (showDiscountColumn) 5: const pw.FixedColumnWidth(45),
        showDiscountColumn ? 6 : 5: const pw.FixedColumnWidth(62),
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
                    _totalsRow(
                      'Summe Warenwert',
                      _formatMoney(_displayGoodsValue(data), data.currency, true),
                    ),
                    _totalsRow(
                      'Versand',
                      _formatMoney(totals.shipping, data.currency, true),
                    ),
                    _totalsRow(
                      'PayPal-Gebühr',
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

  double _displayGoodsValue(InvoiceDocumentData data) {
    final basis = data.priceBasis.trim().toLowerCase();
    if (basis == 'gross') {
      return data.totals.itemsGross;
    }
    return data.totals.itemsNet;
  }

  pw.Widget _totalsRow(String label, String value, {bool bold = false}) {
    final labelStyle = pw.TextStyle(
      fontSize: bold ? 10 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    final valueStyle = pw.TextStyle(
      fontSize: 8.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: _totalsLabelWidth,
            child: pw.Text(label, style: labelStyle),
          ),
          pw.SizedBox(width: _totalsInnerGap),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: _totalsValueRightInset),
                child: pw.Text(value, style: valueStyle),
              ),
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
          '${useGerman ? 'Warengewicht' : 'Total weight'}: ${_formatWeight(data.totals.totalWeightInGram, useGerman)}',
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
    final countryLine = _displayCountryForAddress(party.countryCode);
    final parts = <String>[
      if (_valid(party.company)) party.company,
      if (_valid(_joinValid([party.street, party.houseNumber])))
        _joinValid([party.street, party.houseNumber]),
      if (_valid(_joinValid([party.postalCode, party.city])))
        _joinValid([party.postalCode, party.city]),
      if (_valid(countryLine)) countryLine,
    ];
    return parts.join(' | ');
  }

  bool _isGermanAddress(String value) {
    final upper = value.trim().toUpperCase();
    return upper == 'DE' ||
        upper == 'DEU' ||
        upper == 'GER' ||
        upper == 'GERMANY' ||
        upper == 'DEUTSCHLAND';
  }

  String _displayCountryForAddress(String value, {bool showGermany = false}) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') {
      return '';
    }
    final upper = normalized.toUpperCase();
    if (!showGermany &&
        (upper == 'DE' ||
            upper == 'DEU' ||
            upper == 'GER' ||
            upper == 'GERMANY' ||
            upper == 'DEUTSCHLAND')) {
      return '';
    }

    switch (upper) {
      case 'AT':
        return 'Austria';
      case 'CH':
        return 'Switzerland';
      case 'FR':
        return 'France';
      case 'IT':
        return 'Italy';
      case 'ES':
        return 'Spain';
      case 'NL':
        return 'Netherlands';
      case 'BE':
        return 'Belgium';
      case 'PL':
        return 'Poland';
      case 'CZ':
        return 'Czech Republic';
      case 'US':
      case 'USA':
        return 'United States';
      case 'GB':
      case 'UK':
        return 'United Kingdom';
      case 'DE':
      case 'DEU':
      case 'GER':
      case 'GERMANY':
      case 'DEUTSCHLAND':
        return 'Germany';
      default:
        return normalized;
    }
  }

  String _joinValid(List<String?> values) {
    return values
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty && value != '-')
        .join(' ')
        .trim();
  }

  String _normalizeWebUrl(String value) {
    final raw = value.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    return 'https://$raw';
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
