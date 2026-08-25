import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../order/domain/invoice_models.dart';

class InvoicePdfService {
  const InvoicePdfService();

  // Quick calibration knobs for near-pixel invoice matching.
  static const String _logoAssetPath =
      'lib/images/af_schrift_plus_heartbeat.png';
  static const String _pdfFontRegularAssetPath = 'lib/fonts/Roboto-Regular.ttf';
  static const String _pdfFontBoldAssetPath = 'lib/fonts/Roboto-Bold.ttf';
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
  static const double _invoiceTableHeaderFontSize = 7.0;
  static const double _invoiceTablePriceColumnWidth = 58;
  static const double _invoiceTableArticleColumnWidth = 80;
  static const String _giroRecipient = 'Arrow-Engineering UG';
  static const String _giroIban = 'DE47 6025 0010 1000 835 126';
  static const String _paypalRecipient = 'sales@arrow-fix.com';

  Future<List<int>> generatePdfBytes(InvoiceDocumentData data) async {
    final document = pw.Document();
    // Prefer NotoSans (better Unicode coverage) if available, then Roboto, then built-ins
    pw.Font? embeddedBaseFont;
    pw.Font? embeddedBoldFont;

    try {
      embeddedBaseFont = await _loadPdfFont('lib/fonts/NotoSans-Regular.ttf');
      embeddedBoldFont = await _loadPdfFont('lib/fonts/NotoSans-Bold.ttf');
    } catch (_) {
      // ignore
    }

    embeddedBaseFont ??= await _loadPdfFont(_pdfFontRegularAssetPath);
    embeddedBoldFont ??= await _loadPdfFont(_pdfFontBoldAssetPath);

    final baseFont = embeddedBaseFont ?? pw.Font.helvetica();
    final boldFont = embeddedBoldFont ?? pw.Font.helveticaBold();
    final useGerman = data.language.trim().toUpperCase() == 'DE';
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final showDeliveryAddressRubric = _shouldShowDeliveryAddressRubric(data);
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
          if (showDeliveryAddressRubric)
            _buildParties(data, useGerman)
          else
            pw.Opacity(opacity: 0, child: _buildParties(data, useGerman)),
          pw.SizedBox(height: 16),
          _buildOrderMetaRow(data, useGerman),
          pw.SizedBox(height: 8),
          _buildInvoiceHeadline(data, useGerman),
          pw.SizedBox(height: 2),
          _buildIntroSection(data, useGerman),
          pw.SizedBox(height: 8),
          _buildLinesTable(data, useGerman),
          if (!isPackingList) ...[
            pw.SizedBox(height: 10),
            _buildTotalsSection(data, useGerman),
          ],
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
    final numberToken = _normalizedNumberToken(
      data.orderId,
      data.invoiceNumber,
    );
    final customerLastNameToken = _normalizedLastNameToken(data.buyer.lastName);
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final deliveryDifferent = _isDeliveryAddressDifferent(data);
    // Determine raw end-customer name: prefer a meaningful delivery.lastName
    // but if it's identical to the buyer's last name and delivery.name
    // contains additional tokens, prefer delivery.name to extract the
    // true end-customer surname (covers cases like "BAUMANN WEINFURTER").
    String endCustomerRaw;
    final rawDeliveryLast = data.delivery.lastName.trim();
    final rawDeliveryName = data.delivery.name.trim();
    // buyer last name is available via parameter when needed; no local var.

    final deliveryNameTokens = rawDeliveryName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (deliveryNameTokens.length > 1) {
      // If delivery.name looks like a full name (multiple tokens), prefer it.
      endCustomerRaw = rawDeliveryName;
    } else if (rawDeliveryLast.isNotEmpty && rawDeliveryLast != '-') {
      endCustomerRaw = rawDeliveryLast;
    } else {
      endCustomerRaw = rawDeliveryName;
    }

    final endCustomerLastNameToken = deliveryDifferent
        ? _normalizedEndCustomerLastNameToken(endCustomerRaw, data.buyer.lastName)
        : null;

    if (isPackingList) {
      if (deliveryDifferent && endCustomerLastNameToken != null) {
        return '${numberToken}_${customerLastNameToken}_${endCustomerLastNameToken}_pl.pdf';
      }
      return '${numberToken}_${customerLastNameToken}_pl.pdf';
    }

    final suffix = 'in';
    if (deliveryDifferent && endCustomerLastNameToken != null) {
      return '${numberToken}_${customerLastNameToken}_${endCustomerLastNameToken}_$suffix.pdf';
    }

    return '${numberToken}_${customerLastNameToken}_$suffix.pdf';
  }

  String _normalizedEndCustomerLastNameToken(String rawDeliveryName, [String? buyerLastName]) {
    final parts = rawDeliveryName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty && part != '-')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'Unbekannt';
    }
    if (parts.length == 1) {
      final token = _sanitizeFileNameToken(parts.first);
      return token.isNotEmpty ? token : 'Unbekannt';
    }

    String norm(String s) => s.trim().toUpperCase();

    // "BAUMANN WEINFURTER" style: buyer last matches first token → second token is end-customer surname.
    if (buyerLastName != null && norm(parts.first) == norm(buyerLastName)) {
      final token = _sanitizeFileNameToken(parts[1]);
      if (token.isNotEmpty) return token;
    }

    // "WEINFURTER Peter" style: first token is ALL-CAPS, rest contain lowercase → first is surname.
    final firstAllUpper = parts.first.toUpperCase() == parts.first &&
        parts.first.contains(RegExp(r'[A-Z]'));
    final restHasLower = parts.skip(1).any((p) => p != p.toUpperCase());
    if (firstAllUpper && restHasLower) {
      final token = _sanitizeFileNameToken(parts.first);
      if (token.isNotEmpty) return token;
    }

    // Fallback: "Anna Schmidt" style → last token is surname.
    for (var index = parts.length - 1; index >= 0; index--) {
      final token = _sanitizeFileNameToken(parts[index]);
      if (token.isNotEmpty) return token;
    }

    return 'Unbekannt';
  }

  bool _isDeliveryAddressDifferent(InvoiceDocumentData data) {
    final buyerStreet = _normalizedAddressField(data.buyer.street);
    final deliveryStreet = _normalizedAddressField(data.delivery.street);
    final buyerHouseNumber = _normalizedAddressField(data.buyer.houseNumber);
    final deliveryHouseNumber = _normalizedAddressField(data.delivery.houseNumber);
    final buyerPostalCode = _normalizedAddressField(data.buyer.postalCode);
    final deliveryPostalCode = _normalizedAddressField(data.delivery.postalCode);
    final buyerCity = _normalizedAddressField(data.buyer.city);
    final deliveryCity = _normalizedAddressField(data.delivery.city);
    final buyerState = _normalizedAddressField(data.buyer.state);
    final deliveryState = _normalizedAddressField(data.delivery.state);
    final buyerCountryCode = _normalizedAddressField(data.buyer.countryCode)
        .toUpperCase();
    final deliveryCountryCode = _normalizedAddressField(data.delivery.countryCode)
        .toUpperCase();

    return buyerStreet != deliveryStreet ||
        buyerHouseNumber != deliveryHouseNumber ||
        buyerPostalCode != deliveryPostalCode ||
        buyerCity != deliveryCity ||
      buyerState != deliveryState ||
        buyerCountryCode != deliveryCountryCode;
  }

  String _normalizedAddressField(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') {
      return '';
    }
    return value;
  }

  @visibleForTesting
  bool debugShouldShowDeliveryAddressRubric(InvoiceDocumentData data) {
    return _shouldShowDeliveryAddressRubric(data);
  }

  @visibleForTesting
  bool debugUsesBuyerForShippingRubric(InvoiceDocumentData data) {
    return identical(_shippingRubricParty(data), data.buyer);
  }

  InvoicePartyData _recipientForWindowAddress(InvoiceDocumentData data) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    if (isPackingList && _isDeliveryAddressDifferent(data)) {
      return data.delivery;
    }
    return data.buyer;
  }

  InvoicePartyData _shippingRubricParty(InvoiceDocumentData data) {
    if (!_isDeliveryAddressDifferent(data)) {
      return data.buyer;
    }
    return data.delivery;
  }

  bool _shouldShowDeliveryAddressRubric(InvoiceDocumentData data) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    return !isPackingList || _isDeliveryAddressDifferent(data);
  }

  String _normalizedNumberToken(String orderId, String invoiceNumber) {
    final orderDigits = orderId.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (orderDigits.isNotEmpty) {
      return orderDigits;
    }

    final invoiceDigits = invoiceNumber
        .replaceAll(RegExp(r'[^0-9]'), '')
        .trim();
    if (invoiceDigits.isNotEmpty) {
      return invoiceDigits;
    }

    return '0000000000';
  }

  String _normalizedLastNameToken(String rawLastName) {
    final parts = rawLastName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty && part != '-')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'Unbekannt';
    }

    final normalizedParts = parts
        .map(_sanitizeFileNameToken)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (normalizedParts.isEmpty) {
      return 'Unbekannt';
    }

    return normalizedParts.join('_');
  }

  String _sanitizeFileNameToken(String raw) {
    final ascii = _replaceGermanChars(raw)
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2007', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (ascii.isEmpty) {
      return '';
    }

    return ascii;
  }

  String _replaceGermanChars(String value) {
    return value
        .replaceAll('Ae', 'Ae')
        .replaceAll('Oe', 'Oe')
        .replaceAll('Ue', 'Ue')
        .replaceAll('ae', 'ae')
        .replaceAll('oe', 'oe')
        .replaceAll('ue', 'ue')
        .replaceAll('Ä', 'Ae')
        .replaceAll('Ö', 'Oe')
        .replaceAll('Ü', 'Ue')
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
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

  Future<pw.Font?> _loadPdfFont(String assetPath) async {
    // Try loading from asset bundle first (normal app), then fall back to
    // reading the file directly from the filesystem (tests / dart runs).
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (_) {
      // fallthrough to file-based load
    }

    try {
      final file = File(assetPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {
      // ignore and return null
    }

    return null;
  }

  pw.Widget _buildHeader(
    InvoiceDocumentData data,
    bool useGerman,
    pw.MemoryImage? logoImage,
  ) {
    final recipient = _recipientForWindowAddress(data);
    final buyerHouseNumberFirst = _shouldPlaceHouseNumberFirst(
      countryCode: recipient.countryCode,
      useGerman: useGerman,
    );
    final sellerHouseNumberFirst = _shouldPlaceHouseNumberFirst(
      countryCode: data.seller.countryCode,
      useGerman: useGerman,
    );

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
                  style: const pw.TextStyle(
                    fontSize: 7.6,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 1),
                _buildPartyBlock(
                  '',
                  recipient,
                  useGerman: useGerman,
                  isProforma: data.isProforma,
                  includeContacts: false,
                  includeVat: false,
                  boxed: false,
                  bodyFontSize: 10.8,
                  houseNumberFirst: buyerHouseNumberFirst,
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
                  useGerman: useGerman,
                  isProforma: data.isProforma,
                  includeContacts: true,
                  includeVat: true,
                  boxed: false,
                  addGermanStreetCityGap: false,
                  showGermanyCountry: true,
                  addCountryGap: false,
                  houseNumberFirst: sellerHouseNumberFirst,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildParties(InvoiceDocumentData data, bool useGerman) {
    final shippingParty = _shippingRubricParty(data);
    final deliveryHouseNumberFirst = _shouldPlaceHouseNumberFirst(
      countryCode: shippingParty.countryCode,
      useGerman: useGerman,
    );

    final deliveryDifferent = _isDeliveryAddressDifferent(data);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: pw.SizedBox()),
        pw.SizedBox(width: _addressColumnsGap),
        pw.SizedBox(
          width: _rightAlignedBlockWidth,
          child: _buildPartyBlock(
            useGerman ? 'Lieferadresse' : 'Shipping address',
            shippingParty,
            useGerman: useGerman,
            isProforma: data.isProforma,
            includeContacts: false,
            includeVat: false,
            boxed: false,
            showGermanyCountry: deliveryDifferent,
            houseNumberFirst: deliveryHouseNumberFirst,
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
    final leftDate = data.orderDate.trim().isEmpty
        ? data.invoiceDate
        : data.orderDate;

    return pw.Row(
      children: [
        pw.Expanded(child: _metaCell(leftLabel, leftDate)),
        pw.SizedBox(width: 20),
        pw.Expanded(child: _metaCell(centerLabel, referenceInitials)),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: _metaCell(rightLabel, data.invoiceDate, alignRight: true),
        ),
      ],
    );
  }

  pw.Widget _metaCell(String label, String value, {bool alignRight = false}) {
    final cross = alignRight
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;
    return pw.Column(
      crossAxisAlignment: cross,
      children: [
        pw.Text(
          _sanitizePdfText(label),
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey700,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(_sanitizePdfText(value), style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildInvoiceHeadline(InvoiceDocumentData data, bool useGerman) {
    final label = _buildInvoiceHeadlineLabel(data, useGerman);
    final documentNumber = data.orderId.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey500, height: 0.4),
        pw.SizedBox(height: 6),
        pw.Text(
          _sanitizePdfText('$label: $documentNumber'),
          style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  @visibleForTesting
  String debugBuildInvoiceHeadlineLabel(InvoiceDocumentData data, bool useGerman) {
    return _buildInvoiceHeadlineLabel(data, useGerman);
  }

  String _buildInvoiceHeadlineLabel(InvoiceDocumentData data, bool useGerman) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    if (isPackingList) {
      return useGerman ? 'Lieferschein' : 'Packing List';
    }

    if (data.isProforma) {
      return useGerman
          ? 'Bestellung / Proforma Rechnung-Nr.'
          : 'Order / Proforma invoice no.';
    }

    return useGerman ? 'Bestellung / Rechnung-Nr.' : 'Order / Invoice no.';
  }

  pw.Widget _buildIntroSection(InvoiceDocumentData data, bool useGerman) {
    final introLines = debugBuildIntroLines(data, useGerman);
    final useLegacyGermanResellerLayout = _useLegacyGermanResellerLayout(
      data,
      useGerman,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final line in introLines)
          pw.Text(
            _sanitizePdfText(line.text),
            style: pw.TextStyle(
              fontSize: useLegacyGermanResellerLayout ? 9 : (line.bold ? 9 : 8.6),
              fontWeight: line.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
      ],
    );
  }

  @visibleForTesting
  List<({String text, bool bold})> debugBuildIntroLines(
    InvoiceDocumentData data,
    bool useGerman,
  ) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final gratitude = useGerman
        ? 'Wir danken für Ihre Bestellung und berechnen wie folgt:'
        : 'Thank you for your order. We charge as follows:';
    final lines = <({String text, bool bold})>[];

    final hasIntraCommunityNote =
      useGerman &&
      !isPackingList &&
      data.totals.vatRate <= 0 &&
      _valid(data.buyer.vatId);
    if (hasIntraCommunityNote) {
      lines.add((
        text: 'Innergemeinschaftliche Lieferung, Ihre USt.-ID: ${data.buyer.vatId}',
        bold: false,
      ));
    }

    final hasEnglishTaxFreeIntraCommunityNote =
        !useGerman &&
        !isPackingList &&
        data.isReseller &&
        data.isNoVatCustomer &&
        _valid(data.buyer.vatId);
    if (hasEnglishTaxFreeIntraCommunityNote) {
      lines.add((
        text: 'Taxfree intra-Community delivery VAT#: ${data.buyer.vatId}',
        bold: true,
      ));
    }

    if (!isPackingList) {
      lines.add((text: gratitude, bold: true));
    }

    return lines;
  }

  pw.Widget _buildPartyBlock(
    String title,
    InvoicePartyData party, {
    required bool useGerman,
    bool isProforma = false,
    bool includeContacts = true,
    bool includeVat = true,
    bool boxed = true,
    double bodyFontSize = 9.6,
    bool addGermanStreetCityGap = true,
    bool showGermanyCountry = false,
    bool addCountryGap = true,
    bool houseNumberFirst = false,
  }) {
    final countryLine = _displayCountryForAddress(
      party.countryCode,
      showGermany: showGermanyCountry,
    );
    final isGermany = _isGermanAddress(party.countryCode);
    final streetLine = _streetAddressLine(
      street: party.street,
      houseNumber: party.houseNumber,
      houseNumberFirst: houseNumberFirst,
    );
    final postalCityLine = _postalCityLine(
      party,
      useGerman: useGerman,
      isProforma: isProforma,
    );
    final widgets = <pw.Widget>[
      if (_valid(party.company))
        _partyLine(party.company, fontSize: bodyFontSize),
      if (_valid(party.name)) _partyLine(party.name, fontSize: bodyFontSize),
      if (_valid(streetLine)) _partyLine(streetLine, fontSize: bodyFontSize),
      if (addGermanStreetCityGap && isGermany && _valid(postalCityLine))
        pw.SizedBox(height: 10),
      if (_valid(postalCityLine))
        _partyLine(postalCityLine, fontSize: bodyFontSize),
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
          ? pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500))
          : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (_valid(title)) ...[
            pw.Text(
              title,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10.2,
              ),
            ),
            pw.SizedBox(height: 3),
          ],
          ...widgets,
        ],
      ),
    );
  }

  pw.Widget _partyLine(String text, {double fontSize = 9.6}) {
    return pw.Text(
      _sanitizePdfText(text),
      style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1.15),
    );
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
        pw.Text(
          _sanitizePdfText(label),
          style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1.15),
        ),
        pw.UrlLink(
          destination: url,
          child: pw.Text(
            _sanitizePdfText(linkText),
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
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final showDiscountColumn =
        !isPackingList &&
        data.lines.any((line) => line.discountPercent.abs() > 0.0001);
    final headers = _lineTableHeaders(
      data: data,
      useGerman: useGerman,
      showDiscountColumn: showDiscountColumn,
    );

    final rows = data.lines
        .map((line) {
          return <String>[
            line.position.toString(),
            _sanitizePdfText(line.articleLabel),
            _sanitizePdfText(line.description, preserveLineBreaks: true),
            line.quantity.toString(),
            if (!isPackingList)
              _formatMoney(line.unitPrice, data.currency, useGerman),
            if (showDiscountColumn) line.discountPercent.toStringAsFixed(1),
            if (!isPackingList)
              _formatMoney(line.lineTotal, data.currency, useGerman),
          ];
        })
        .toList(growable: false);

    const accentRed = PdfColor(0.82, 0.18, 0.16);

    return pw.TableHelper.fromTextArray(
      headers: headers.map(_noWrapHeaderText).toList(growable: false),
      data: rows,
      headerDecoration: const pw.BoxDecoration(),
      headerStyle: pw.TextStyle(
        fontSize: _invoiceTableHeaderFontSize,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: <int, pw.Alignment>{
        3: pw.Alignment.center,
        if (!isPackingList) 4: pw.Alignment.centerRight,
        if (showDiscountColumn) 5: pw.Alignment.center,
        if (!isPackingList)
          (showDiscountColumn ? 6 : 5): pw.Alignment.centerRight,
      },
      border: pw.TableBorder(
        top: const pw.BorderSide(color: accentRed, width: 0.9),
        bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.4),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.3,
        ),
        verticalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.3,
        ),
      ),
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FixedColumnWidth(30),
        1: const pw.FixedColumnWidth(_invoiceTableArticleColumnWidth),
        3: const pw.FixedColumnWidth(40),
        if (!isPackingList)
          4: const pw.FixedColumnWidth(_invoiceTablePriceColumnWidth),
        if (showDiscountColumn) 5: const pw.FixedColumnWidth(45),
        if (!isPackingList)
          (showDiscountColumn ? 6 : 5):
              const pw.FixedColumnWidth(_invoiceTablePriceColumnWidth),
      },
    );
  }

  @visibleForTesting
  List<String> debugBuildLineHeaders({
    required InvoiceDocumentData data,
    required bool useGerman,
    required bool showDiscountColumn,
  }) {
    return _lineTableHeaders(
      data: data,
      useGerman: useGerman,
      showDiscountColumn: showDiscountColumn,
    );
  }

  @visibleForTesting
  String debugSanitizePdfText(String text, {bool preserveLineBreaks = false}) {
    return _sanitizePdfText(text, preserveLineBreaks: preserveLineBreaks);
  }

  List<String> _lineTableHeaders({
    required InvoiceDocumentData data,
    required bool useGerman,
    required bool showDiscountColumn,
  }) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final isNetBasis = data.priceBasis.trim().toLowerCase() == 'net';

    return <String>[
      useGerman ? 'Pos' : 'Pos.',
      useGerman ? 'Artikel' : 'ID',
      useGerman ? 'Bezeichnung' : 'Description',
      useGerman ? 'Menge' : 'Qty',
      if (!isPackingList)
        useGerman
            ? 'Einzelpreis'
            : (isNetBasis ? 'Unit price (net)' : 'Unit price'),
      if (showDiscountColumn) useGerman ? 'Rabatt %' : 'Discount %',
      if (!isPackingList)
        useGerman
            ? 'Gesamtpreis'
            : (isNetBasis ? 'Total (net)' : 'Total'),
    ];
  }

  pw.Widget _buildTotalsSection(InvoiceDocumentData data, bool useGerman) {
    final totals = data.totals;
    final isGrossBasis = data.priceBasis.trim().toLowerCase() == 'gross';
    final displayShipping = _displayShipping(data);
    final displayPayPalFee = _displayPayPalFee(data);
    final displayGrandTotal = _displayGrandTotal(data);
    final germanGoodsLabel = isGrossBasis
        ? 'Summe Warenwert'
        : 'Summe Warenwert netto';
    final hideVatAndGoodsGross = _isEnglishNetOutsideEu(data);
    final vatHint = useGerman
        ? '${totals.vatRate.toStringAsFixed(0)}% MwSt. im Warenwert enthalten'
        : isGrossBasis
        ? 'Goods value incl. VAT (${totals.vatRate.toStringAsFixed(0)}%)'
        : 'VAT (${totals.vatRate.toStringAsFixed(0)}%) included in goods value';

    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                totals.vatRate <= 0 ? '' : vatHint,
                style: const pw.TextStyle(
                  fontSize: 8.6,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.SizedBox(
              width: _totalsBlockWidth,
              child: pw.Column(
                children: [
                  if (useGerman) ...[
                    _totalsRow(
                      germanGoodsLabel,
                      _formatMoney(
                        _displayGoodsValue(data),
                        data.currency,
                        true,
                      ),
                    ),
                    if (displayShipping.abs() > 0.0001)
                      _totalsRow(
                        'Versand',
                        _formatMoney(displayShipping, data.currency, true),
                      ),
                    if (displayPayPalFee.abs() > 0.0001)
                      _totalsRow(
                        'PayPal-Gebühr',
                        _formatMoney(displayPayPalFee, data.currency, true),
                      ),
                    pw.Divider(color: PdfColors.grey600, height: 0.4),
                    _totalsRow(
                      'Endbetrag',
                      _formatMoney(displayGrandTotal, data.currency, true),
                      bold: true,
                    ),
                  ] else ...[
                    if (!isGrossBasis)
                      _totalsRow(
                        'Goods net',
                        _formatMoney(totals.itemsNet, data.currency, false),
                      ),
                    if (!isGrossBasis && !hideVatAndGoodsGross)
                      _totalsRow(
                        'VAT (${totals.vatRate.toStringAsFixed(1)}%)',
                        _formatMoney(totals.vatAmount, data.currency, false),
                      ),
                    if (!hideVatAndGoodsGross)
                      _totalsRow(
                        isGrossBasis ? 'Goods value' : 'Goods gross',
                        _formatMoney(totals.itemsGross, data.currency, false),
                      ),
                    if (displayShipping.abs() > 0.0001)
                      _totalsRow(
                        'Shipping',
                        _formatMoney(displayShipping, data.currency, false),
                      ),
                    if (displayPayPalFee.abs() > 0.0001)
                      _totalsRow(
                        'PayPal fee',
                        _formatMoney(displayPayPalFee, data.currency, false),
                      ),
                    pw.Divider(color: PdfColors.grey600, height: 0.4),
                    _totalsRow(
                      isGrossBasis ? 'Grand Total' : 'Grand total',
                      _formatMoney(displayGrandTotal, data.currency, false),
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
                padding: const pw.EdgeInsets.only(
                  right: _totalsValueRightInset,
                ),
                child: pw.Text(value, style: valueStyle),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetaSection(InvoiceDocumentData data, bool useGerman) {
    final isPackingList = data.documentKind == InvoiceDocumentKind.packingList;
    final displayTrackingCode = _displayTrackingCode(data.trackingCode);
    if (isPackingList) {
      final packingListMetaLines = _packingListMetaLines(
        data: data,
        useGerman: useGerman,
        displayTrackingCode: displayTrackingCode,
      );
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(color: PdfColors.grey500, height: 0.3),
          pw.SizedBox(height: 4),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    packingListMetaLines.first,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Expanded(child: pw.SizedBox()),
                ],
              ),
              for (final line in packingListMetaLines.skip(1)) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  line,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ],
          ),
        ],
      );
    }

    final noteTitle = useGerman ? 'Hinweis' : 'Note';
    final paymentTitle = useGerman ? 'Zahlung' : 'Payment';
    final payDateTitle = useGerman ? 'Zahldatum' : 'Pay date';
    final deliveryTitle = useGerman ? 'Lieferdatum' : 'Delivery date';
    final trackingTitle = useGerman ? 'Tracking' : 'Tracking';

    final hideGiroCode = _isEnglishNetOutsideEu(data);
    final giroCodePayload = _buildGiroCodePayload(data);
    final showPayPalQr =
      _isPayPalPayment(data.paymentLabel) && !_hideShippingAndPayPalForProforma(data);
    final paypalCodePayload = showPayPalQr ? _buildPayPalQrPayload(data) : null;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey500, height: 0.3),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (_valid(data.note))
                    pw.Text(
                      '$noteTitle: ${data.note}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (_shouldShowPaymentLabel(data))
                    pw.Text(
                      '$paymentTitle: ${data.paymentLabel}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (_valid(data.payDate))
                    pw.Text(
                      '$payDateTitle: ${data.payDate}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (_valid(data.deliveryDate))
                    pw.Text(
                      '$deliveryTitle: ${data.deliveryDate}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (_valid(displayTrackingCode))
                    pw.Text(
                      '$trackingTitle: $displayTrackingCode',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '${useGerman ? 'Warengewicht' : 'Total weight of goods'}: ${_formatWeight(data.totals.totalWeightInGram, useGerman)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (showPayPalQr) ...[
                  _buildPayPalCodeBox(paypalCodePayload!),
                  pw.SizedBox(width: 8),
                ],
                if (!hideGiroCode)
                  _buildGiroCodeBox(
                    giroCodePayload,
                    hasPaypalFee: _displayPayPalFee(data) > 0.0001,
                    useGerman: useGerman,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @visibleForTesting
  List<String> debugBuildPackingListMetaLines(
    InvoiceDocumentData data,
    bool useGerman,
  ) {
    return _packingListMetaLines(
      data: data,
      useGerman: useGerman,
      displayTrackingCode: _displayTrackingCode(data.trackingCode),
    );
  }

  List<String> _packingListMetaLines({
    required InvoiceDocumentData data,
    required bool useGerman,
    required String displayTrackingCode,
  }) {
    final noteTitle = useGerman ? 'Lieferhinweis' : 'Delivery note';
    final trackingTitle = useGerman ? 'Trackingcode' : 'Tracking';
    final lines = <String>[
      '${useGerman ? 'Warengewicht' : 'Total weight of goods'}: ${_formatWeight(data.totals.totalWeightInGram, useGerman)}',
    ];

    if (_valid(data.note)) {
      lines.add('$noteTitle: ${data.note}');
    }
    if (_valid(displayTrackingCode)) {
      lines.add('$trackingTitle: $displayTrackingCode');
    }

    return lines;
  }

  pw.Widget _buildGiroCodeBox(
    String payload, {
    required bool hasPaypalFee,
    required bool useGerman,
  }) {
    final label = hasPaypalFee
        ? (useGerman
              ? 'GiroCode\nohne PayPal-Gebühr'
              : 'GiroCode\nwithout PayPal fee')
        : 'GiroCode';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 46,
          height: 46,
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.4),
          ),
          child: pw.BarcodeWidget(data: payload, barcode: pw.Barcode.qrCode()),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7.5),
        ),
      ],
    );
  }

  pw.Widget _buildPayPalCodeBox(String payload) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 46,
          height: 46,
          padding: const pw.EdgeInsets.all(2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.4),
          ),
          child: pw.BarcodeWidget(data: payload, barcode: pw.Barcode.qrCode()),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'PayPal QR-Code',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7.5),
        ),
      ],
    );
  }

  String _buildGiroCodePayload(InvoiceDocumentData data) {
    final paypalFee = _displayPayPalFee(data) > 0 ? _displayPayPalFee(data) : 0.0;
    final effectiveAmount = _displayGrandTotal(data) - paypalFee;
    final amount = effectiveAmount < 0 ? 0.0 : effectiveAmount;
    final amountToken = amount.toStringAsFixed(2);
    final iban = _giroIban.replaceAll(' ', '').trim();
    final purpose = _giroPurpose(data);

    return [
      'BCD',
      '002',
      '1',
      'SCT',
      '',
      _giroRecipient,
      iban,
      'EUR$amountToken',
      '',
      '',
      purpose,
      '',
    ].join('\n');
  }

  String _giroPurpose(InvoiceDocumentData data) {
    final invoiceReference = data.orderId.trim().isNotEmpty
        ? data.orderId.trim()
        : data.invoiceNumber.trim();
    if (invoiceReference.length <= 140) {
      return invoiceReference;
    }
    return invoiceReference.substring(0, 140);
  }

  String _buildPayPalQrPayload(InvoiceDocumentData data) {
    final reference = _giroPurpose(data);
    final amount = _displayGrandTotal(data) < 0 ? 0.0 : _displayGrandTotal(data);
    final amountToken = amount.toStringAsFixed(2);
    final currency = data.currency.trim().isEmpty
        ? 'EUR'
        : data.currency.trim().toUpperCase();

    final uri = Uri.https('www.paypal.com', '/cgi-bin/webscr', {
      'cmd': '_xclick',
      'business': _paypalRecipient,
      'amount': amountToken,
      'currency_code': currency,
      'item_name': reference,
      'invoice': reference,
    });
    return uri.toString();
  }

  bool _isPayPalPayment(String paymentLabel) {
    return paymentLabel.trim().toLowerCase() == 'paypal';
  }

  bool _hideShippingAndPayPalForProforma(InvoiceDocumentData data) {
    final isInvoice = data.documentKind == InvoiceDocumentKind.invoice;
    return isInvoice && data.isProforma;
  }

  bool _shouldShowPaymentLabel(InvoiceDocumentData data) {
    if (!_valid(data.paymentLabel)) {
      return false;
    }
    if (_hideShippingAndPayPalForProforma(data) &&
        _isPayPalPayment(data.paymentLabel)) {
      return false;
    }
    return true;
  }

  @visibleForTesting
  bool debugShouldShowPaymentLabel(InvoiceDocumentData data) {
    return _shouldShowPaymentLabel(data);
  }

  double _displayShipping(InvoiceDocumentData data) {
    if (_hideShippingAndPayPalForProforma(data)) {
      return 0.0;
    }
    return data.totals.shipping;
  }

  double _displayPayPalFee(InvoiceDocumentData data) {
    if (_hideShippingAndPayPalForProforma(data)) {
      return 0.0;
    }
    return data.totals.paypalFee;
  }

  double _displayGrandTotal(InvoiceDocumentData data) {
    if (!_hideShippingAndPayPalForProforma(data)) {
      return data.totals.grandTotal;
    }

    final adjusted =
        data.totals.grandTotal - data.totals.shipping - data.totals.paypalFee;
    return adjusted < 0 ? 0.0 : adjusted;
  }

  @visibleForTesting
  ({double shipping, double paypalFee, double grandTotal})
      debugDisplayTotals(InvoiceDocumentData data) {
    return (
      shipping: _displayShipping(data),
      paypalFee: _displayPayPalFee(data),
      grandTotal: _displayGrandTotal(data),
    );
  }

  bool _isEnglishNetOutsideEu(InvoiceDocumentData data) {
    final isEnglish = data.language.trim().toUpperCase() == 'EN';
    final isNet = data.priceBasis.trim().toLowerCase() == 'net';
    final country = _deliveryCountryToken(data);
    final isOutsideEu = country.isNotEmpty && !_isEuCountry(country);
    return isEnglish && isNet && isOutsideEu;
  }

  String _deliveryCountryToken(InvoiceDocumentData data) {
    final delivery = data.delivery.countryCode.trim().toUpperCase();
    if (delivery.isNotEmpty && delivery != '-') {
      return delivery;
    }
    final buyer = data.buyer.countryCode.trim().toUpperCase();
    if (buyer.isNotEmpty && buyer != '-') {
      return buyer;
    }
    return '';
  }

  bool _isEuCountry(String countryToken) {
    const euCountryTokens = <String>{
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
      'EL',
      'HU', 'HUN', 'HUNGARY',
      'IE', 'IRL', 'IRELAND',
      'IT', 'ITA', 'ITALY', 'ITALIA',
      'LV', 'LVA', 'LATVIA',
      'LT', 'LTU', 'LITHUANIA',
      'LU', 'LUX', 'LUXEMBOURG',
      'MT', 'MLT', 'MALTA',
      'NL', 'NLD', 'NETHERLANDS', 'HOLLAND', 'NIEDERLANDE',
      'PL', 'POL', 'POLAND',
      'PT', 'PRT', 'PORTUGAL',
      'RO', 'ROU', 'ROMANIA',
      'SK', 'SVK', 'SLOVAKIA',
      'SI', 'SVN', 'SLOVENIA',
      'ES', 'ESP', 'SPAIN',
      'SE', 'SWE', 'SWEDEN',
    };
    return euCountryTokens.contains(countryToken.trim().toUpperCase());
  }

  pw.Widget _buildCompanyFooter(InvoiceDocumentData data) {
    final useGerman = data.language.trim().toUpperCase() == 'DE';

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
          pw.Expanded(
            child: _footerColumn(
              _localizedFooterLines(data.footer.leftLines, useGerman),
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: _footerColumn(
              _localizedFooterLines(data.footer.centerLines, useGerman),
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: _footerColumn(
              _localizedFooterLines(data.footer.rightLines, useGerman),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _localizedFooterLines(List<String> lines, bool useGerman) {
    if (useGerman) {
      return lines;
    }

    return lines
        .map((line) {
          final trimmed = line.trim();
          if (trimmed == 'Sitz des Unternehmens: Fellbach') {
            return 'Company Headquarters: Fellbach, Germany';
          }
          if (trimmed.startsWith('Registergericht:')) {
            return trimmed.replaceFirst('Registergericht:', 'Registration:');
          }
          if (trimmed.startsWith('USt-ID-Nr:')) {
            return trimmed.replaceFirst('USt-ID-Nr:', 'VAT-No:');
          }
          if (trimmed.startsWith('Geschäftsführer:')) {
            return trimmed.replaceFirst(
              'Geschäftsführer:',
              'Managing Director:',
            );
          }
          if (trimmed.startsWith('Bankverbindung:')) {
            return trimmed.replaceFirst('Bankverbindung:', 'Bank Account:');
          }
          return line;
        })
        .toList(growable: false);
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
              child: pw.Text(
                _sanitizePdfText(line),
                style: const pw.TextStyle(fontSize: 7.8, lineSpacing: 1.1),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String _singleLineAddress(InvoicePartyData party) {
    final countryLine = _displayCountryForAddress(party.countryCode);
    final postalCityLine = _postalCityLine(party, useGerman: true);
    final houseNumberFirst = _shouldPlaceHouseNumberFirst(
      countryCode: party.countryCode,
      useGerman: true,
    );
    final parts = <String>[
      if (_valid(party.company)) party.company,
      if (_valid(
        _streetAddressLine(
          street: party.street,
          houseNumber: party.houseNumber,
          houseNumberFirst: houseNumberFirst,
        ),
      ))
        _streetAddressLine(
          street: party.street,
          houseNumber: party.houseNumber,
          houseNumberFirst: houseNumberFirst,
        ),
      if (_valid(postalCityLine)) postalCityLine,
      if (_valid(countryLine)) countryLine,
    ];
    return _sanitizePdfText(parts.join(' | '));
  }

  bool _shouldPlaceHouseNumberFirst({
    required String countryCode,
    required bool useGerman,
  }) {
    if (_isUsAddress(countryCode)) {
      return true;
    }
    if (_isDutchAddress(countryCode)) {
      return true;
    }
    if (_isUkAddress(countryCode)) {
      return true;
    }
    if (!useGerman && _isAustralianAddress(countryCode)) {
      return true;
    }
    return false;
  }

  bool _isUkAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'GB' ||
        upper == 'UK' ||
        upper == 'GBR' ||
        upper == 'UNITED KINGDOM' ||
        upper == 'VEREINIGTES KÖNIGREICH' ||
        upper == 'VEREINIGTES KOENIGREICH';
  }

  bool _isDutchAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'NL' ||
        upper == 'NLD' ||
        upper == 'NETHERLANDS' ||
        upper == 'HOLLAND' ||
        upper == 'NIEDERLANDE';
  }

  String _postalCityLine(
    InvoicePartyData party, {
    required bool useGerman,
    bool isProforma = false,
  }) {
    final isItaly = _isItalianAddress(party.countryCode);
    final isSwitzerland = _isSwitzerlandAddress(party.countryCode);
    final isUsAddress = _isUsAddress(party.countryCode);
    final isAustralianEnglish = !useGerman &&
        _isAustralianAddress(party.countryCode);
    final isUsOrAustralia = _isUsOrAustraliaAddress(party.countryCode);
    final isPostalAfterCityCountry = _isPostalAfterCityCountry(
      party.countryCode,
    );
    final city = party.city.trim();
    final state = party.state.trim();
    final stateToken = isAustralianEnglish
      ? _abbreviateAustralianState(state)
      : (isUsAddress ? _abbreviateUsState(state) : state);
    final swissCantonCode = _swissCantonCodeFromAdministrativeUnit(state);
    final cityWithSwissCanton =
      swissCantonCode == null || city.isEmpty || city == '-'
        ? city
        : '$city $swissCantonCode';
    final postalCode = party.postalCode.trim();

    if (isSwitzerland) {
      return _joinValid([postalCode, cityWithSwissCanton]);
    }

    if (isUsOrAustralia) {
      if (isUsAddress) {
        final cityAlreadyContainsState = _cityContainsUsStateCode(
          city,
          stateToken,
        );
        return _joinValid([
          city,
          if (!cityAlreadyContainsState) stateToken,
          postalCode,
        ]);
      }
      return _joinValid([city, stateToken, postalCode]);
    }

    if (isPostalAfterCityCountry) {
      return _joinValid([city, stateToken, postalCode]);
    }

    final cityToken =
      isItaly
        ? _formatItalianCityWithProvinceCode(city: city, administrativeUnit: state)
        : city;

    return _joinValid([postalCode, cityToken]);
  }

  bool _isSwitzerlandAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'CH' ||
        upper == 'CHE' ||
        upper == 'SWITZERLAND' ||
        upper == 'SCHWEIZ' ||
        upper == 'SUISSE' ||
        upper == 'SVIZZERA';
  }

  String? _swissCantonCodeFromAdministrativeUnit(String administrativeUnit) {
    final trimmed = administrativeUnit.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return null;
    }

    final startCodeMatch = RegExp(r'^([A-Za-z]{2})\b').firstMatch(trimmed);
    if (startCodeMatch != null) {
      return startCodeMatch.group(1)?.toUpperCase();
    }

    final isoMatch = RegExp(r'\bCH[-\s]?([A-Za-z]{2})\b', caseSensitive: false)
        .firstMatch(trimmed);
    if (isoMatch != null) {
      return isoMatch.group(1)?.toUpperCase();
    }

    return null;
  }

  String _formatItalianCityWithProvinceCode({
    required String city,
    required String administrativeUnit,
  }) {
    final trimmedCity = city.trim();
    if (trimmedCity.isEmpty || trimmedCity == '-') {
      return trimmedCity;
    }

    final provinceCode = _italianProvinceCodeFromAdministrativeUnit(
      administrativeUnit,
    );
    if (provinceCode == null) {
      return trimmedCity;
    }

    final cleanedCity = trimmedCity
        .replaceFirst(RegExp(r'\s*\([A-Za-z]{2}\)\s*$'), '')
        .trim();
    if (cleanedCity.isEmpty) {
      return trimmedCity;
    }

    return '$cleanedCity ($provinceCode)';
  }

  String? _italianProvinceCodeFromAdministrativeUnit(String administrativeUnit) {
    final normalized = administrativeUnit.trim();
    if (normalized.isEmpty || normalized == '-') {
      return null;
    }

    final startCodeMatch = RegExp(r'^([A-Za-z]{2})\b').firstMatch(normalized);
    if (startCodeMatch != null) {
      return startCodeMatch.group(1)?.toUpperCase();
    }

    final parenthesizedCodeMatch = RegExp(r'\(([A-Za-z]{2})\)')
        .firstMatch(normalized);
    if (parenthesizedCodeMatch != null) {
      return parenthesizedCodeMatch.group(1)?.toUpperCase();
    }

    final isoCodeMatch = RegExp(r'\bIT[-\s]?([A-Za-z]{2})\b', caseSensitive: false)
        .firstMatch(normalized);
    if (isoCodeMatch != null) {
      return isoCodeMatch.group(1)?.toUpperCase();
    }

    return RegExp(r'^[A-Za-z]{2}$').hasMatch(normalized)
        ? normalized.toUpperCase()
        : null;
  }

  bool _isItalianAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'IT' ||
        upper == 'ITA' ||
        upper == 'ITALY' ||
        upper == 'ITALIEN' ||
        upper == 'ITALIA';
  }

  bool _isUsOrAustraliaAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'US' ||
        upper == 'USA' ||
        upper == 'UNITED STATES' ||
        upper == 'VEREINIGTE STAATEN' ||
        upper == 'AU' ||
        upper == 'AUS' ||
        upper == 'AUSTRALIA' ||
        upper == 'AUSTRALIEN';
  }

  bool _isUsAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'US' ||
        upper == 'USA' ||
        upper == 'UNITED STATES' ||
        upper == 'VEREINIGTE STAATEN';
  }

  String _abbreviateUsState(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') {
      return normalized;
    }

    final startCodeMatch = RegExp(r'^([A-Za-z]{2})\b').firstMatch(normalized);
    if (startCodeMatch != null) {
      return startCodeMatch.group(1)!.toUpperCase();
    }

    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(normalized)) {
      return normalized.toUpperCase();
    }

    return normalized;
  }

  bool _cityContainsUsStateCode(String city, String stateCode) {
    final normalizedCity = city.trim().toUpperCase();
    final normalizedState = stateCode.trim().toUpperCase();
    if (normalizedCity.isEmpty || normalizedState.isEmpty) {
      return false;
    }
    return normalizedCity.endsWith(', $normalizedState') ||
        normalizedCity.endsWith(' $normalizedState') ||
        normalizedCity == normalizedState;
  }

  @visibleForTesting
  String debugPostalCityLine(
    InvoicePartyData party, {
    required bool useGerman,
    bool isProforma = false,
  }) {
    return _postalCityLine(
      party,
      useGerman: useGerman,
      isProforma: isProforma,
    );
  }

  @visibleForTesting
  String debugStreetAddressLine(
    InvoicePartyData party, {
    required bool useGerman,
  }) {
    final houseNumberFirst = _shouldPlaceHouseNumberFirst(
      countryCode: party.countryCode,
      useGerman: useGerman,
    );
    return _streetAddressLine(
      street: party.street,
      houseNumber: party.houseNumber,
      houseNumberFirst: houseNumberFirst,
    );
  }

  bool _isAustralianAddress(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'AU' ||
        upper == 'AUS' ||
        upper == 'AUSTRALIA' ||
        upper == 'AUSTRALIEN';
  }

  String _abbreviateAustralianState(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') {
      return normalized;
    }

    final upper = normalized.toUpperCase();
    final cleaned = upper
        .replaceAll(RegExp(r'[_\-/(),.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    bool hasToken(String token) {
      return RegExp('(^| )${RegExp.escape(token)}( |\$)').hasMatch(cleaned);
    }

    if (cleaned.contains('NEW SOUTH WALES') || hasToken('NSW')) {
      return 'NSW';
    }
    if (cleaned.contains('VICTORIA') || hasToken('VIC')) {
      return 'VIC';
    }
    if (cleaned.contains('QUEENSLAND') || hasToken('QLD')) {
      return 'QLD';
    }
    if (cleaned.contains('SOUTH AUSTRALIA') || hasToken('SA')) {
      return 'SA';
    }
    if (cleaned.contains('WESTERN AUSTRALIA') || hasToken('WA')) {
      return 'WA';
    }
    if (cleaned.contains('TASMANIA') || hasToken('TAS')) {
      return 'TAS';
    }
    if (cleaned.contains('NORTHERN TERRITORY') || hasToken('NT')) {
      return 'NT';
    }
    if (cleaned.contains('AUSTRALIAN CAPITAL TERRITORY') || hasToken('ACT')) {
      return 'ACT';
    }

    switch (cleaned) {
      case 'NEW SOUTH WALES':
      case 'NSW':
        return 'NSW';
      case 'VICTORIA':
      case 'VIC':
        return 'VIC';
      case 'QUEENSLAND':
      case 'QLD':
        return 'QLD';
      case 'SOUTH AUSTRALIA':
      case 'SA':
        return 'SA';
      case 'WESTERN AUSTRALIA':
      case 'WA':
        return 'WA';
      case 'TASMANIA':
      case 'TAS':
        return 'TAS';
      case 'NORTHERN TERRITORY':
      case 'NT':
        return 'NT';
      case 'AUSTRALIAN CAPITAL TERRITORY':
      case 'ACT':
        return 'ACT';
      default:
        return cleaned;
    }
  }

  bool _isPostalAfterCityCountry(String countryCode) {
    final upper = countryCode.trim().toUpperCase();
    return upper == 'GB' ||
        upper == 'UK' ||
        upper == 'GBR' ||
        upper == 'UNITED KINGDOM' ||
        upper == 'VEREINIGTES KÖNIGREICH' ||
        upper == 'VEREINIGTES KOENIGREICH' ||
        upper == 'CA' ||
        upper == 'CAN' ||
        upper == 'CANADA' ||
        upper == 'NZ' ||
        upper == 'NZL' ||
        upper == 'NEW ZEALAND' ||
        upper == 'NEUSEELAND' ||
        upper == 'IE' ||
        upper == 'IRL' ||
        upper == 'IRELAND' ||
        upper == 'IRLAND';
  }

  String _streetAddressLine({
    required String street,
    required String houseNumber,
    required bool houseNumberFirst,
  }) {
    if (_isPoBoxStreet(street)) {
      return _joinValid([street, houseNumber]);
    }

    if (houseNumberFirst) {
      return _joinValid([houseNumber, street]);
    }
    return _joinValid([street, houseNumber]);
  }

  bool _isPoBoxStreet(String street) {
    final normalized = street
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized == 'POBOX';
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
      case 'AU':
      case 'AUS':
      case 'AUSTRALIA':
      case 'AUSTRALIEN':
        return 'Australia';
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

  String _displayTrackingCode(String rawTrackingCode) {
    var normalized = rawTrackingCode.trim();
    if (!_valid(normalized)) {
      return '-';
    }

    final firstWhitespace = normalized.indexOf(RegExp(r'\s'));
    if (firstWhitespace >= 0 && firstWhitespace + 1 <= normalized.length) {
      normalized = normalized.substring(firstWhitespace + 1).trimLeft();
    }

    if (normalized.isEmpty) {
      return '-';
    }

    final hasAlphanumeric = RegExp(r'[A-Za-z0-9]').hasMatch(normalized);
    return hasAlphanumeric ? normalized : '-';
  }

  bool _useLegacyGermanResellerLayout(InvoiceDocumentData data, bool useGerman) {
    return useGerman &&
        data.documentKind == InvoiceDocumentKind.invoice &&
        data.isReseller &&
        _valid(data.buyer.vatId);
  }

  String _sanitizePdfText(String text, {bool preserveLineBreaks = false}) {
    if (text.isEmpty) {
      return text;
    }

    final normalizedLineBreaks = text
        .replaceAll('\\r\\n', '\n')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u21B5', '\n')
        .replaceAll('\u21B2', '\n')
        .replaceAll('\u23CE', '\n');

    final sanitized = normalizedLineBreaks
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2007', ' ')
        .replaceAll('\u202F', ' ')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201A', ',')
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u201E', '"')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2026', '...');

    final withoutControls = sanitized.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );

    if (preserveLineBreaks) {
      return withoutControls;
    }

    return withoutControls
        .replaceAll('\r\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  String _noWrapHeaderText(String text) {
    final sanitized = _sanitizePdfText(text);
    return sanitized.replaceAll(' ', '\u00A0');
  }

  bool _valid(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isNotEmpty && normalized != '-';
  }
}
