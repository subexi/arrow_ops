import '../../customer/data/customer_repository.dart';
import '../../customer/domain/customer.dart';
import '../../order/data/invoice_calculation_service.dart';
import '../../order/data/order_repository.dart';
import '../../order/domain/invoice_models.dart';
import '../../order/domain/order_models.dart';

class InvoiceSellerProfile {
  const InvoiceSellerProfile({
    this.name = '',
    this.company = '-',
    this.street = '-',
    this.houseNumber = '-',
    this.postalCode = '-',
    this.city = '-',
    this.countryCode = '-',
    this.vatId = '-',
    this.email = '-',
    this.phone = '-',
    this.web = '-',
    this.footerLeftLines = const <String>[
      'Sitz des Unternehmens: Fellbach',
      'Registergericht: Stuttgart',
      'HRB 732452',
      'USt-ID-Nr: DE268366503',
    ],
    this.footerCenterLines = const <String>['Geschäftsführer: Helmut Dittrich'],
    this.footerRightLines = const <String>[
      'Bankverbindung: Kreissparkasse Waiblingen',
      'Kto.: 1000 835 126 | BLZ: 602 500 10',
      'BIC / SWIFT: SOLADES1WBN',
      'IBAN: DE47 6025 0010 1000 835 126',
      'PayPal: sales@arrow-fix.com',
    ],
  });

  final String name;
  final String company;
  final String street;
  final String houseNumber;
  final String postalCode;
  final String city;
  final String countryCode;
  final String vatId;
  final String email;
  final String phone;
  final String web;
  final List<String> footerLeftLines;
  final List<String> footerCenterLines;
  final List<String> footerRightLines;

  static const InvoiceSellerProfile defaultProfile = InvoiceSellerProfile(
    company: 'Arrow-Engineering UG',
    street: 'Lange Furche',
    houseNumber: '13',
    postalCode: '70736',
    city: 'Fellbach',
    countryCode: 'Germany',
    email: 'sales@arrow-fix.com',
    phone: '+49 171 53 86 301',
    web: 'www.arrow-fix.com',
  );
}

class InvoiceDocumentBuildService {
  InvoiceDocumentBuildService({
    OrderRepository? orderRepository,
    CustomerRepository? customerRepository,
    InvoiceCalculationService? calculationService,
  }) : _orderRepository = orderRepository ?? const OrderRepository(),
       _customerRepository = customerRepository ?? const CustomerRepository(),
       _calculationService =
           calculationService ?? const InvoiceCalculationService();

  final OrderRepository _orderRepository;
  final CustomerRepository _customerRepository;
  final InvoiceCalculationService _calculationService;

  Future<InvoiceDocumentData> buildFromOrder({
    required String orderId,
    InvoiceDocumentKind documentKind = InvoiceDocumentKind.invoice,
    InvoiceSellerProfile sellerProfile = InvoiceSellerProfile.defaultProfile,
    String? invoiceNumber,
    String? invoiceDate,
    String? noteOverride,
  }) async {
    final order = await _orderRepository.getOrderById(orderId);
    if (order == null) {
      throw StateError('Order not found for id: $orderId');
    }

    final customer = await _customerRepository.getById(order.oCustomerId);
    if (customer == null) {
      throw StateError('Customer not found for id: ${order.oCustomerId}');
    }

    final enforceEnglishLines = _shouldEnforceEnglishDescriptions(
      order: order,
      customer: customer,
    );
    final items = await _orderRepository.getItemsForOrder(order.oId);
    final lines = _calculationService.buildLines(
      items: items,
      language: order.oLanguage,
      forceEnglishOnly: enforceEnglishLines,
    );
    final totals = _calculationService.calculateTotals(
      order: order,
      items: items,
      customer: customer,
    );
    final isReseller = customer.cDealer || order.oDealer == 1;
    final effectivePriceBasis =
        (isReseller && customer.cVat)
            ? 'net'
            : _normalizedOrFallback(order.oPriceBasis, 'net');

    return InvoiceDocumentData(
      documentKind: documentKind,
      invoiceNumber: _normalizedOrFallback(
        invoiceNumber,
        _defaultInvoiceNumber(order),
      ),
      invoiceDate: _normalizedInvoiceDate(invoiceDate, order),
      orderDate: _normalizedOrFallback(order.oDate, ''),
      orderId: order.oId,
      currency: _normalizedOrFallback(order.oCurrency, 'EUR'),
      language: _normalizedOrFallback(order.oLanguage, 'DE'),
        priceBasis: effectivePriceBasis,
        isReseller: isReseller,
      isNoVatCustomer: customer.cVat,
      seller: _buildSeller(sellerProfile),
      buyer: _buildBuyer(customer),
      delivery: _buildDelivery(order, customer),
      footer: _buildFooter(sellerProfile),
      lines: lines,
      totals: totals,
      note: _normalizedOrFallback(
        noteOverride,
        _normalizedOrFallback(order.oNote, '-'),
      ),
      paymentLabel: _paymentLabel(order.oPayment),
      payDate: _normalizedOrFallback(order.oPayDate, ''),
      deliveryDate: _normalizedOrFallback(order.oDelivery, ''),
      trackingCode: _normalizedOrFallback(order.oTrackingCode, '-'),
    );
  }

  InvoicePartyData _buildSeller(InvoiceSellerProfile profile) {
    return InvoicePartyData(
      name: _normalizedOrFallback(profile.name, ''),
      company: _normalizedOrFallback(profile.company, '-'),
      street: _normalizedOrFallback(profile.street, ''),
      houseNumber: _normalizedOrFallback(profile.houseNumber, ''),
      postalCode: _normalizedOrFallback(profile.postalCode, ''),
      city: _normalizedOrFallback(profile.city, ''),
      state: '',
      countryCode: _normalizedOrFallback(profile.countryCode, ''),
      vatId: _normalizedOrFallback(profile.vatId, ''),
      email: _normalizedOrFallback(profile.email, ''),
      phone: _normalizedOrFallback(profile.phone, ''),
      web: _normalizedOrFallback(profile.web, ''),
    );
  }

  InvoicePartyData _buildBuyer(Customer customer) {
    final buyerName = _customerName(customer);

    return InvoicePartyData(
      name: buyerName.isEmpty ? '-' : buyerName,
      lastName: _normalizedOrFallback(customer.cLastName, '-'),
      company: _normalizedOrFallback(customer.cCompany, '-'),
      street: _normalizedOrFallback(customer.cStreetB, '-'),
      houseNumber: _normalizedOrFallback(customer.cHouseNumberB, '-'),
      postalCode: _normalizedOrFallback(customer.cPostalCodeB, '-'),
      city: _normalizedOrFallback(customer.cCityB, '-'),
      state: _normalizedOrFallback(customer.cStateB, ''),
      countryCode: _normalizedOrFallback(
        customer.cCountryBId,
        '-',
      ).toUpperCase(),
      vatId: _normalizedOrFallback(customer.cVatId, '-'),
      email: _normalizedOrFallback(customer.cMail, '-'),
      phone: _normalizedOrFallback(customer.cPhone, '-'),
      web: '-',
    );
  }

  InvoicePartyData _buildDelivery(OrderRow order, Customer customer) {
    final deliveryName = _deliveryName(order, customer);

    return InvoicePartyData(
      name: deliveryName.isEmpty ? '-' : deliveryName,
      lastName: _normalizedOrFallback(customer.cLastName, '-'),
      company: '-',
      street: _deliveryValue(
        orderValue: order.oDeliveryStreet,
        customerValue: customer.cStreetD,
      ),
      houseNumber: _deliveryValue(
        orderValue: order.oDeliveryHouseNumber,
        customerValue: customer.cHouseNumberD,
      ),
      postalCode: _deliveryValue(
        orderValue: order.oDeliveryPostalCode,
        customerValue: customer.cPostalCodeD,
      ),
      city: _deliveryValue(
        orderValue: order.oDeliveryCity,
        customerValue: customer.cCityD,
      ),
      state: _deliveryValue(
        orderValue: order.oDeliveryState,
        customerValue: customer.cStateD,
      ),
      countryCode: _deliveryCountryToken(order, customer),
      vatId: _normalizedOrFallback(customer.cVatId, '-'),
      email: _normalizedOrFallback(customer.cMail, '-'),
      phone: _normalizedOrFallback(customer.cPhone, '-'),
      web: '-',
    );
  }

  String _deliveryName(OrderRow order, Customer customer) {
    final explicitOrderName =
        _normalizedOrFallback(order.oDeliveryName, '').trim();
    if (explicitOrderName.isNotEmpty && explicitOrderName != '-') {
      return explicitOrderName;
    }

    final explicitDeliveryName =
        _normalizedOrFallback(customer.cCareofD, '').trim();
    if (explicitDeliveryName.isNotEmpty && explicitDeliveryName != '-') {
      return explicitDeliveryName;
    }
    return _customerName(customer);
  }

  String _deliveryValue({
    required String orderValue,
    required String customerValue,
  }) {
    final normalizedOrderValue = _normalizedOrFallback(orderValue, '').trim();
    if (normalizedOrderValue.isNotEmpty && normalizedOrderValue != '-') {
      return normalizedOrderValue;
    }
    return _normalizedOrFallback(customerValue, '-');
  }

  InvoiceFooterData _buildFooter(InvoiceSellerProfile profile) {
    return InvoiceFooterData(
      leftLines: _normalizeLines(profile.footerLeftLines),
      centerLines: _normalizeLines(profile.footerCenterLines),
      rightLines: _normalizeLines(profile.footerRightLines),
    );
  }

  String _customerName(Customer customer) {
    return '${_normalizedOrFallback(customer.cFirstName, '').trim()} ${_normalizedOrFallback(customer.cLastName, '').trim()}'
        .trim();
  }

  String _defaultInvoiceNumber(OrderRow order) {
    final dateDigits = _digitsOnly(order.oDate);
    final suffix = dateDigits.isEmpty ? _todayDigits() : dateDigits;
    return 'INV-$suffix-${order.oId}';
  }

  String _normalizedInvoiceDate(String? preferredDate, OrderRow order) {
    final explicit = _normalizedOrFallback(preferredDate, '');
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final fromOrder = _normalizedOrFallback(order.oDate, '');
    if (fromOrder.isNotEmpty) {
      return fromOrder;
    }
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _paymentLabel(int paymentCode) {
    switch (paymentCode) {
      case 1:
        return 'PayPal';
      case 2:
        return 'Bank transfer';
      case 3:
        return 'Cash';
      default:
        return '-';
    }
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _todayDigits() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}$month$day';
  }

  String _normalizedOrFallback(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  List<String> _normalizeLines(List<String> lines) {
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line != '-')
        .toList(growable: false);
  }

  bool _shouldEnforceEnglishDescriptions({
    required OrderRow order,
    required Customer customer,
  }) {
    final isEnglish = _normalizedOrFallback(order.oLanguage, 'DE')
            .toUpperCase() ==
        'EN';
    final isNet =
        _normalizedOrFallback(order.oPriceBasis, 'net').toLowerCase() == 'net';
    final country = _deliveryCountryToken(order, customer);
    final isOutsideEu = country.isNotEmpty && !_isEuCountry(country);
    return isEnglish && isNet && isOutsideEu;
  }

  String _deliveryCountryToken(OrderRow order, Customer customer) {
    final orderDelivery = _normalizedOrFallback(order.oDeliveryCountryId, '')
        .toUpperCase();
    if (orderDelivery.isNotEmpty && orderDelivery != '-') {
      return orderDelivery;
    }

    final delivery = _normalizedOrFallback(customer.cCountryDId, '').toUpperCase();
    if (delivery.isNotEmpty && delivery != '-') {
      return delivery;
    }
    final billing = _normalizedOrFallback(customer.cCountryBId, '')
        .toUpperCase();
    if (billing.isNotEmpty && billing != '-') {
      return billing;
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
}
