enum InvoiceDocumentKind { invoice, packingList }

class InvoiceDocumentData {
  const InvoiceDocumentData({
    this.documentKind = InvoiceDocumentKind.invoice,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.orderDate,
    required this.orderId,
    required this.currency,
    required this.language,
    required this.priceBasis,
    required this.isReseller,
    required this.isNoVatCustomer,
    required this.seller,
    required this.buyer,
    required this.delivery,
    required this.footer,
    required this.lines,
    required this.totals,
    this.note = '-',
    this.paymentLabel = '-',
    this.payDate = '',
    this.deliveryDate = '',
    this.trackingCode = '-',
  });

  final InvoiceDocumentKind documentKind;
  final String invoiceNumber;
  final String invoiceDate;
  final String orderDate;
  final String orderId;
  final String currency;
  final String language;
  final String priceBasis;
  final bool isReseller;
  final bool isNoVatCustomer;
  final InvoicePartyData seller;
  final InvoicePartyData buyer;
  final InvoicePartyData delivery;
  final InvoiceFooterData footer;
  final List<InvoiceLineData> lines;
  final InvoiceTotalsData totals;
  final String note;
  final String paymentLabel;
  final String payDate;
  final String deliveryDate;
  final String trackingCode;
}

class InvoiceFooterData {
  const InvoiceFooterData({
    this.leftLines = const <String>[],
    this.centerLines = const <String>[],
    this.rightLines = const <String>[],
  });

  final List<String> leftLines;
  final List<String> centerLines;
  final List<String> rightLines;
}

class InvoicePartyData {
  const InvoicePartyData({
    required this.name,
    this.lastName = '-',
    this.company = '-',
    this.street = '-',
    this.houseNumber = '-',
    this.postalCode = '-',
    this.city = '-',
    this.state = '',
    this.countryCode = '-',
    this.vatId = '-',
    this.email = '-',
    this.phone = '-',
    this.web = '-',
  });

  final String name;
  final String lastName;
  final String company;
  final String street;
  final String houseNumber;
  final String postalCode;
  final String city;
  final String state;
  final String countryCode;
  final String vatId;
  final String email;
  final String phone;
  final String web;
}

class InvoiceLineData {
  const InvoiceLineData({
    required this.position,
    required this.articleId,
    required this.articleLabel,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    required this.lineTotal,
    required this.weightInGram,
    this.hts = '-',
    this.color = '-',
  });

  final int position;
  final int articleId;
  final String articleLabel;
  final String description;
  final int quantity;
  final double unitPrice;
  final double discountPercent;
  final double lineTotal;
  final double weightInGram;
  final String hts;
  final String color;
}

class InvoiceTotalsData {
  const InvoiceTotalsData({
    required this.itemsNet,
    required this.vatRate,
    required this.vatAmount,
    required this.itemsGross,
    required this.shipping,
    required this.paypalFee,
    required this.grandTotal,
    required this.totalWeightInGram,
  });

  final double itemsNet;
  final double vatRate;
  final double vatAmount;
  final double itemsGross;
  final double shipping;
  final double paypalFee;
  final double grandTotal;
  final double totalWeightInGram;
}
