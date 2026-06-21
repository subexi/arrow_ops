class OrderRow {
  const OrderRow({
    required this.oId,
    required this.oCustomerId,
    this.oDealer = 0,
    this.oDate = '',
    this.oCurrency = 'EUR',
    this.oLanguage = 'DE',
    this.oPriceBasis = 'net',
    this.oVatRate = 0,
    this.oShipping = 0,
    this.oValueGoods = 0,
    this.oTotalPrice = 0,
    this.oVat = 0,
    this.oTotalWeight = 0,
    this.oPayDate = '',
    this.oPayment = 0,
    this.oPaypalFee = 0,
    this.oDelivery = '',
    this.oTradeShow = '',
    this.oPutt = 0,
    this.oTrackingCode = '',
    this.oNote = '-',
  });

  final String oId;
  final String oCustomerId;
  final int oDealer;
  final String oDate;
  final String oCurrency;
  final String oLanguage;
  final String oPriceBasis;
  final double oVatRate;
  final double oShipping;
  final double oValueGoods;
  final double oTotalPrice;
  final double oVat;
  final double oTotalWeight;
  final String oPayDate;
  final int oPayment;
  final double oPaypalFee;
  final String oDelivery;
  final String oTradeShow;
  final int oPutt;
  final String oTrackingCode;
  final String oNote;

  factory OrderRow.fromMap(Map<String, Object?> map) {
    return OrderRow(
      oId: _str(map['o_id']),
      oCustomerId: _str(map['o_customer_id']),
      oDealer: _int(map['o_dealer']),
      oDate: _str(map['o_date']),
      oCurrency: _str(map['o_currency'], fallback: 'EUR'),
      oLanguage: _str(map['o_language'], fallback: 'DE'),
      oPriceBasis: _str(map['o_price_basis'], fallback: 'net'),
      oVatRate: _double(map['o_vat_rate']),
      oShipping: _double(map['o_shipping']),
      oValueGoods: _double(map['o_value_goods']),
      oTotalPrice: _double(map['o_total_price']),
      oVat: _double(map['o_vat']),
      oTotalWeight: _double(map['o_total_weight']),
      oPayDate: _str(map['o_pay_date']),
      oPayment: _int(map['o_payment']),
      oPaypalFee: _double(map['o_paypal_fee']),
      oDelivery: _str(map['o_delivery']),
      oTradeShow: _str(map['o_trade_show']),
      oPutt: _int(map['o_putt']),
      oTrackingCode: _str(map['o_tracking_code']),
      oNote: _str(map['o_note'], fallback: '-'),
    );
  }

  Map<String, Object?> toMap() => {
        'o_id': oId,
        'o_customer_id': oCustomerId,
        'o_dealer': oDealer,
        'o_date': oDate,
        'o_currency': oCurrency,
        'o_language': oLanguage,
        'o_price_basis': oPriceBasis,
        'o_vat_rate': oVatRate,
        'o_shipping': oShipping,
        'o_value_goods': oValueGoods,
        'o_total_price': oTotalPrice,
        'o_vat': oVat,
        'o_total_weight': oTotalWeight,
        'o_pay_date': oPayDate,
        'o_payment': oPayment,
        'o_paypal_fee': oPaypalFee,
        'o_delivery': oDelivery,
        'o_trade_show': oTradeShow,
        'o_putt': oPutt,
        'o_tracking_code': oTrackingCode,
        'o_note': oNote,
      };

  OrderRow copyWith({
    String? oId,
    String? oCustomerId,
    int? oDealer,
    String? oDate,
    String? oCurrency,
    String? oLanguage,
    String? oPriceBasis,
    double? oVatRate,
    double? oShipping,
    double? oValueGoods,
    double? oTotalPrice,
    double? oVat,
    double? oTotalWeight,
    String? oPayDate,
    int? oPayment,
    double? oPaypalFee,
    String? oDelivery,
    String? oTradeShow,
    int? oPutt,
    String? oTrackingCode,
    String? oNote,
  }) =>
      OrderRow(
        oId: oId ?? this.oId,
        oCustomerId: oCustomerId ?? this.oCustomerId,
        oDealer: oDealer ?? this.oDealer,
        oDate: oDate ?? this.oDate,
        oCurrency: oCurrency ?? this.oCurrency,
        oLanguage: oLanguage ?? this.oLanguage,
        oPriceBasis: oPriceBasis ?? this.oPriceBasis,
        oVatRate: oVatRate ?? this.oVatRate,
        oShipping: oShipping ?? this.oShipping,
        oValueGoods: oValueGoods ?? this.oValueGoods,
        oTotalPrice: oTotalPrice ?? this.oTotalPrice,
        oVat: oVat ?? this.oVat,
        oTotalWeight: oTotalWeight ?? this.oTotalWeight,
        oPayDate: oPayDate ?? this.oPayDate,
        oPayment: oPayment ?? this.oPayment,
        oPaypalFee: oPaypalFee ?? this.oPaypalFee,
        oDelivery: oDelivery ?? this.oDelivery,
        oTradeShow: oTradeShow ?? this.oTradeShow,
        oPutt: oPutt ?? this.oPutt,
        oTrackingCode: oTrackingCode ?? this.oTrackingCode,
        oNote: oNote ?? this.oNote,
      );

  static String _str(Object? v, {String fallback = ''}) =>
      v?.toString().trim().isEmpty == true ? fallback : (v?.toString().trim() ?? fallback);

  static int _int(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;

  static double _double(Object? v) =>
      double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

class ItemOrderedRow {
  const ItemOrderedRow({
    this.ioId,
    required this.ioOrderId,
    this.ioPos = 0,
    this.ioQuantity = 1,
    this.ioItemId = 0,
    this.ioIdi = '',
    this.ioDescriptionDeLong = '',
    this.ioDescriptionEnLong = '',
    this.ioHts = '-',
    this.ioColor = '-',
    this.ioUnitPrice = 0,
    this.ioDiscount = 0,
    this.ioTotalPrice = 0,
    this.ioItemWeight = 0,
    this.ioTotalWeight = 0,
    this.ioPhoto = '-',
  });

  final int? ioId;
  final String ioOrderId;
  final int ioPos;
  final int ioQuantity;
  final int ioItemId;
  final String ioIdi;
  final String ioDescriptionDeLong;
  final String ioDescriptionEnLong;
  final String ioHts;
  final String ioColor;
  final double ioUnitPrice;
  final double ioDiscount;
  final double ioTotalPrice;
  final double ioItemWeight;
  final double ioTotalWeight;
  final String ioPhoto;

  factory ItemOrderedRow.fromMap(Map<String, Object?> map) {
    return ItemOrderedRow(
      ioId: _nullableInt(map['io_id']),
      ioOrderId: _str(map['io_order_id']),
      ioPos: _int(map['io_pos']),
      ioQuantity: _int(map['io_quantity']),
      ioItemId: _int(map['io_item_id']),
      ioIdi: _str(map['io_idi']),
      ioDescriptionDeLong: _str(map['io_description_de_long']),
      ioDescriptionEnLong: _str(map['io_description_en_long']),
      ioHts: _str(map['io_hts'], fallback: '-'),
      ioColor: _str(map['io_color'], fallback: '-'),
      ioUnitPrice: _double(map['io_unit_price']),
      ioDiscount: _double(map['io_discount']),
      ioTotalPrice: _double(map['io_total_price']),
      ioItemWeight: _double(map['io_item_weight']),
      ioTotalWeight: _double(map['io_total_weight']),
      ioPhoto: _str(map['io_photo'], fallback: '-'),
    );
  }

  Map<String, Object?> toMap() => {
        'io_id': ioId,
        'io_order_id': ioOrderId,
        'io_pos': ioPos,
        'io_quantity': ioQuantity,
        'io_item_id': ioItemId,
        'io_idi': ioIdi,
        'io_description_de_long': ioDescriptionDeLong,
        'io_description_en_long': ioDescriptionEnLong,
        'io_hts': ioHts,
        'io_color': ioColor,
        'io_unit_price': ioUnitPrice,
        'io_discount': ioDiscount,
        'io_total_price': ioTotalPrice,
        'io_item_weight': ioItemWeight,
        'io_total_weight': ioTotalWeight,
        'io_photo': ioPhoto,
      };

  static String _str(Object? v, {String fallback = ''}) =>
      v?.toString().trim().isEmpty == true ? fallback : (v?.toString().trim() ?? fallback);

  static int _int(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;

  static int? _nullableInt(Object? v) {
    final raw = v?.toString().trim();
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    return int.tryParse(raw);
  }

  static double _double(Object? v) =>
      double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}
