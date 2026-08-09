import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../customer/domain/country_tld.dart';
import '../../../customer/domain/customer.dart';
import '../../../order/domain/order_models.dart';
import '../../domain/paypal_fee_rules.dart';

class OrderFormDialog extends StatefulWidget {
  const OrderFormDialog({
    super.key,
    required this.allCustomers,
    required this.allCountries,
    this.initialValue,
    this.canEditOrderId = true,
    this.assignedItems = const [],
  });

  final List<Customer> allCustomers;
  final List<CountryTld> allCountries;
  final OrderRow? initialValue;
  final bool canEditOrderId;
  final List<ItemOrderedRow> assignedItems;

  @override
  State<OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends State<OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderIdFocusNode = FocusNode();
  final _customerSearchFocusNode = FocusNode();
  final _payDateFocusNode = FocusNode();
  final _deliveryDateFocusNode = FocusNode();
  final _noteFocusNode = FocusNode();
  final _paypalFeeFocusNode = FocusNode();
  Timer? _customerSearchDebounce;

  static const int _maxCustomerSearchResults = 100;

  late final TextEditingController _orderIdController;
  late final TextEditingController _customerSearchController;
  late final TextEditingController _dateController;
  late final TextEditingController _fxToEurController;
  late final TextEditingController _vatRateController;
  late final TextEditingController _shippingController;
  late final TextEditingController _valueGoodsController;
  late final TextEditingController _valueGoodsGrossController;
  late final TextEditingController _totalPriceController;
  late final TextEditingController _vatController;
  late final TextEditingController _totalWeightController;
  late final TextEditingController _payDateController;
  late final TextEditingController _paypalFeeController;
  late final TextEditingController _paypalFeeActualController;
  late final TextEditingController _deliveryController;
  late final TextEditingController _tradeShowController;
  late final TextEditingController _trackingCodeController;
  late final TextEditingController _noteController;
  late final TextEditingController _deliveryNameController;
  late final TextEditingController _deliveryStreetController;
  late final TextEditingController _deliveryHouseNumberController;
  late final TextEditingController _deliveryPostalCodeController;
  late final TextEditingController _deliveryCityController;
  late final TextEditingController _deliveryLatController;
  late final TextEditingController _deliveryLonController;
  late final TextEditingController _deliveryCountryController;
  late String _deliveryCountryId;

  Customer? _selectedCustomer;
  String _currency = 'EUR';
  String _language = 'DE';
  String _priceBasis = 'gross';
  int _payment = 0;
  int? _paymentActual;
  bool _putt = false;
  bool _dealer = false;
  List<Customer> _filteredCustomers = [];
  bool _showCustomerDropdown = false;
  bool _isRecalculatingPaypalFee = false;
  bool _isPaypalFeeManuallyOverridden = false;
  bool _isUpdatingDateFromOrderId = false;
  bool _deliveryAddressDifferent = false;
  bool _isFetchingDeliveryCoordinates = false;

  static const int _paypalPaymentCode = 1;
  static const int _cashPaymentCode = 4;

  bool get _isEditing => widget.initialValue != null;
  bool get _canEditOrderId => !_isEditing || widget.canEditOrderId;
  bool get _isPuttCashOrder => _putt && _payment == _cashPaymentCode;

  static const List<String> _paymentLabels = [
    'Sonstiges',
    'PayPal',
    'Banküberweisung',
    'Kreditkarte',
    'Bar',
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;

    _orderIdController = TextEditingController(text: v?.oId ?? _generateOrderId());
    _customerSearchController = TextEditingController();
    _dateController = TextEditingController(text: v?.oDate ?? _todayString());
    _fxToEurController = TextEditingController(
      text: _decimalText(v?.oFxToEur ?? 1),
    );
    _vatRateController = TextEditingController(text: _decimalText(v?.oVatRate ?? 19));
    _shippingController = TextEditingController(text: _decimalText(v?.oShipping ?? 0));
    _valueGoodsController = TextEditingController(text: _decimalText(v?.oValueGoods ?? 0));
    _valueGoodsGrossController = TextEditingController();
    _totalPriceController = TextEditingController(text: _decimalText(v?.oTotalPrice ?? 0));
    _vatController = TextEditingController(text: _decimalText(v?.oVat ?? 0));
    _totalWeightController = TextEditingController(text: _weightText(v?.oTotalWeight ?? 0));
    _payDateController = TextEditingController(text: v?.oPayDate ?? '');
    _paypalFeeController = TextEditingController(text: _decimalText(v?.oPaypalFee ?? 0));
    _paypalFeeActualController = TextEditingController(
      text: v?.oPaypalFeeActual == null ? '' : _decimalText(v!.oPaypalFeeActual!),
    );
    _deliveryController = TextEditingController(text: v?.oDelivery ?? '');
    _tradeShowController = TextEditingController(text: v?.oTradeShow ?? '');
    _trackingCodeController = TextEditingController(text: v?.oTrackingCode ?? '');
    _noteController = TextEditingController(text: v?.oNote ?? '-');
    _deliveryNameController = TextEditingController(
      text: v?.oDeliveryName ?? '-',
    );
    _deliveryStreetController = TextEditingController(
      text: v?.oDeliveryStreet ?? '-',
    );
    _deliveryHouseNumberController = TextEditingController(
      text: v?.oDeliveryHouseNumber ?? '-',
    );
    _deliveryPostalCodeController = TextEditingController(
      text: v?.oDeliveryPostalCode ?? '-',
    );
    _deliveryCityController = TextEditingController(
      text: v?.oDeliveryCity ?? '-',
    );
    _deliveryLatController = TextEditingController(
      text: (v?.oDeliveryLat ?? 0).toString(),
    );
    _deliveryLonController = TextEditingController(
      text: (v?.oDeliveryLon ?? 0).toString(),
    );
    _deliveryCountryId = _normalizeCountryId(v?.oDeliveryCountryId);
    _deliveryCountryController = TextEditingController(
      text: _countryNameForId(_deliveryCountryId),
    );

    _currency = v?.oCurrency ?? 'EUR';
    _language = v?.oLanguage ?? 'DE';
    _priceBasis = v?.oPriceBasis ?? 'gross';
    _payment = v?.oPayment ?? _paypalPaymentCode;
    _paymentActual = v?.oPaymentActual;
    _putt = (v?.oPutt ?? 0) != 0;
    _dealer = (v?.oDealer ?? 0) != 0;
    _deliveryAddressDifferent = (v?.oDeliveryAddressDifferent ?? 0) != 0;

    _syncFxRateWithCurrency(forceUsdReset: false);
    _syncPriceBasisWithCurrency();
    _setVatRateForPriceBasis();
    _orderIdController.addListener(_syncDateFromOrderId);
    _orderIdFocusNode.addListener(() {
      if (!_orderIdFocusNode.hasFocus) {
        _syncDateFromOrderId();
      }
    });
    _payDateFocusNode.addListener(() {
      _normalizeDateControllerOnBlur(_payDateFocusNode, _payDateController);
    });
    _deliveryDateFocusNode.addListener(() {
      _normalizeDateControllerOnBlur(_deliveryDateFocusNode, _deliveryController);
    });
    _refreshTotalWeightFromAssignedItems();
    _refreshGoodsValuesForCurrentBasis();
    _valueGoodsController.addListener(_refreshGoodsValuesForCurrentBasis);
    _vatController.addListener(_refreshGoodsValuesForCurrentBasis);
    _vatRateController.addListener(_refreshGoodsValuesForCurrentBasis);
    _shippingController.addListener(_refreshTotalPriceForCurrentBasis);
    _paypalFeeController.addListener(_refreshTotalPriceForCurrentBasis);
    _paypalFeeController.addListener(_markPaypalFeeAsManuallyOverridden);
    _fxToEurController.addListener(_recalculatePaypalFeeFromTotalIfApplicable);
    _totalPriceController.addListener(_recalculatePaypalFeeFromTotalIfApplicable);
    _noteFocusNode.addListener(_clearNotePlaceholderOnFocus);

    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _customerSearchFocusNode.requestFocus();
      });
    }

    if (v != null) {
      final existing = widget.allCustomers.cast<Customer?>().firstWhere(
            (c) => c?.cId == v.oCustomerId,
            orElse: () => null,
          );
      _selectedCustomer = existing;
      if (existing != null) {
        _customerSearchController.text = _customerLabel(existing);
        _dealer = existing.cDealer;
        _syncDeliveryFromSelectedCustomer(force: !_deliveryAddressDifferent);
        _applyNoVatCustomerRules();
        _setVatRateForPriceBasis();
        _refreshGoodsValuesForCurrentBasis();

        final calculatedFee = _calculatedPaypalFeeForCurrentInputs();
        if (_payment == _paypalPaymentCode && calculatedFee != null) {
          final savedFee = _parseDecimal(_paypalFeeController);
          _isPaypalFeeManuallyOverridden =
              (savedFee - calculatedFee).abs() > 0.005;
        }

        _recalculatePaypalFeeFromTotalIfApplicable();
      }
    }

    _filteredCustomers = widget.allCustomers;
  }

  @override
  void dispose() {
    _customerSearchDebounce?.cancel();
    _orderIdController.dispose();
    _customerSearchController.dispose();
    _dateController.dispose();
    _fxToEurController.dispose();
    _vatRateController.dispose();
    _shippingController.dispose();
    _valueGoodsController.dispose();
    _valueGoodsGrossController.dispose();
    _totalPriceController.dispose();
    _vatController.dispose();
    _totalWeightController.dispose();
    _payDateController.dispose();
    _paypalFeeController.dispose();
    _paypalFeeActualController.dispose();
    _deliveryController.dispose();
    _tradeShowController.dispose();
    _trackingCodeController.dispose();
    _noteController.dispose();
    _deliveryNameController.dispose();
    _deliveryStreetController.dispose();
    _deliveryHouseNumberController.dispose();
    _deliveryPostalCodeController.dispose();
    _deliveryCityController.dispose();
    _deliveryLatController.dispose();
    _deliveryLonController.dispose();
    _deliveryCountryController.dispose();
    _orderIdFocusNode.dispose();
    _customerSearchFocusNode.dispose();
    _payDateFocusNode.dispose();
    _deliveryDateFocusNode.dispose();
    _paypalFeeFocusNode.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _normalizeDateControllerOnBlur(
    FocusNode focusNode,
    TextEditingController controller,
  ) {
    if (focusNode.hasFocus) {
      return;
    }

    final normalized = _normalizeDateForStorage(controller.text);
    if (normalized == controller.text) {
      return;
    }

    controller.text = normalized;
  }

  void _syncDateFromOrderId() {
    if (_isUpdatingDateFromOrderId) {
      return;
    }
    final derived = _deriveDateFromOrderId(_orderIdController.text);
    if (derived == null || _dateController.text == derived) {
      return;
    }

    _isUpdatingDateFromOrderId = true;
    _dateController.value = TextEditingValue(
      text: derived,
      selection: TextSelection.collapsed(offset: derived.length),
    );
    _isUpdatingDateFromOrderId = false;
  }

  void _clearNotePlaceholderOnFocus() {
    if (!_noteFocusNode.hasFocus) {
      return;
    }

    if (_noteController.text.trim() != '-') {
      return;
    }

    _noteController.clear();
  }

  String _generateOrderId() {
    final now = DateTime.now();
    return '${(now.year % 100).toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  String? _deriveDateFromOrderId(String orderId) {
    final digits = orderId.replaceAll(RegExp(r'\D'), '');
    final match = RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{0,})$').firstMatch(digits);
    if (match == null) {
      return null;
    }

    final year2 = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year2 == null || month == null || day == null) {
      return null;
    }

    final year = year2 >= 70 ? 1900 + year2 : 2000 + year2;
    final date = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (date == null) {
      return null;
    }
    return _formatIsoDate(date);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatIsoDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _normalizeDateForStorage(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    final isoMatch = RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})$').firstMatch(value);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1) ?? '');
      final m = int.tryParse(isoMatch.group(2) ?? '');
      final d = int.tryParse(isoMatch.group(3) ?? '');
      if (y != null && m != null && d != null) {
        final date = DateTime.tryParse('${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
        if (date != null) {
          return _formatIsoDate(date);
        }
      }
    }

    final dmyMatch = RegExp(r'^(\d{1,2})[-./](\d{1,2})[-./](\d{2}|\d{4})$').firstMatch(value);
    if (dmyMatch != null) {
      final d = int.tryParse(dmyMatch.group(1) ?? '');
      final m = int.tryParse(dmyMatch.group(2) ?? '');
      final yRaw = dmyMatch.group(3) ?? '';
      final yParsed = int.tryParse(yRaw);
      if (d != null && m != null && yParsed != null) {
        final y = yRaw.length == 2 ? (yParsed >= 70 ? 1900 + yParsed : 2000 + yParsed) : yParsed;
        final date = DateTime.tryParse('${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
        if (date != null) {
          return _formatIsoDate(date);
        }
      }
    }

    final compactMatch = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (compactMatch != null) {
      final date = DateTime.tryParse('${compactMatch.group(1)}-${compactMatch.group(2)}-${compactMatch.group(3)}');
      if (date != null) {
        return _formatIsoDate(date);
      }
    }

    return value;
  }

  String _decimalText(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _weightText(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  double? _tryParseDecimalFlexible(String rawInput) {
    var raw = rawInput.trim();
    if (raw.isEmpty) {
      return null;
    }

    // Entfernt Währungssymbole und Trenner wie Leerzeichen/Apostroph.
    raw = raw.replaceAll(RegExp(r"[^0-9,\.\-+']"), '');
    raw = raw.replaceAll("'", '');
    if (raw.isEmpty) {
      return null;
    }

    final hasComma = raw.contains(',');
    final hasDot = raw.contains('.');

    String normalized;
    if (hasComma && hasDot) {
      final lastComma = raw.lastIndexOf(',');
      final lastDot = raw.lastIndexOf('.');
      if (lastComma > lastDot) {
        normalized = raw.replaceAll('.', '').replaceAll(',', '.');
      } else {
        normalized = raw.replaceAll(',', '');
      }
    } else if (hasComma) {
      normalized = raw.replaceAll(',', '.');
    } else {
      normalized = raw;
    }

    // Falls mehrere Punkte übrig bleiben: letzte Stelle als Dezimaltrenner,
    // vorherige als Tausendertrenner interpretieren.
    final dotCount = '.'.allMatches(normalized).length;
    if (dotCount > 1) {
      final lastDot = normalized.lastIndexOf('.');
      final integerPart = normalized.substring(0, lastDot).replaceAll('.', '');
      final decimalPart = normalized.substring(lastDot + 1);
      normalized = '$integerPart.$decimalPart';
    }

    return double.tryParse(normalized);
  }

  double _parseDecimal(TextEditingController c) =>
      _tryParseDecimalFlexible(c.text) ?? 0;

  double? _parseOptionalDecimal(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return _tryParseDecimalFlexible(raw);
  }

  String? _validateDecimalFieldValue(
    String? value, {
    required bool allowEmpty,
  }) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return allowEmpty ? null : 'Bitte Zahl eingeben';
    }
    if (_tryParseDecimalFlexible(raw) == null) {
      return 'Bitte gültige Zahl eingeben';
    }
    return null;
  }

  double _plannedEffectivePaypalFee() {
    if (_payment != _paypalPaymentCode) {
      return 0;
    }
    return _parseDecimal(_paypalFeeController);
  }

  double _actualEffectivePaypalFeeForPreview() {
    final parsedActualFee = _parseOptionalDecimal(_paypalFeeActualController);
    if (parsedActualFee != null) {
      return parsedActualFee;
    }
    if (_paymentActual != null && _paymentActual != _paypalPaymentCode) {
      return 0;
    }
    return _plannedEffectivePaypalFee();
  }

  double _netGoodsDeltaFromActualSettlementPreview() {
    return _plannedEffectivePaypalFee() - _actualEffectivePaypalFeeForPreview();
  }

  double _salesVatAmountPreview() {
    return _parseDecimal(_vatController);
  }

  double _potentialFeeTaxEffectPreview() {
    final vatRate = _parseDecimal(_vatRateController);
    if (vatRate <= 0) {
      return 0;
    }

    // Informative Schätzung: zusätzliche/geringere Gebühren wirken sich
    // bei Nettoverbuchung der Gebühr proportional auf den Steueranteil aus.
    final feeDelta = _actualEffectivePaypalFeeForPreview() - _plannedEffectivePaypalFee();
    return feeDelta * (vatRate / 100);
  }

  Widget _buildActualSettlementDeltaHint() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _paypalFeeController,
        _paypalFeeActualController,
        _vatController,
        _vatRateController,
      ]),
      builder: (context, _) {
        final plannedFee = _plannedEffectivePaypalFee();
        final actualFee = _actualEffectivePaypalFeeForPreview();
        final delta = _netGoodsDeltaFromActualSettlementPreview();
        final salesVat = _salesVatAmountPreview();
        final feeTaxEffect = _potentialFeeTaxEffectPreview();
        final isNeutral = delta.abs() < 0.005;
        final sign = delta >= 0 ? '+' : '-';
        final feeTaxSign = feeTaxEffect >= 0 ? '+' : '-';
        final absAmount = _decimalText(delta.abs());
        final salesVatText = _decimalText(salesVat);
        final feeTaxEffectText = _decimalText(feeTaxEffect.abs());
        final plannedText = _decimalText(plannedFee);
        final actualText = _decimalText(actualFee);
        final currencyCode = _currency.toUpperCase();
        final colorScheme = Theme.of(context).colorScheme;
        final baseTextColor = Theme.of(context).textTheme.bodySmall?.color;
        final color = isNeutral
            ? baseTextColor
            : (delta > 0 ? colorScheme.primary : colorScheme.error);

        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Effektive geplante Gebühr: $plannedText $currencyCode',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: baseTextColor),
              ),
              Text(
                'Effektive tatsächliche Gebühr: $actualText $currencyCode',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: baseTextColor),
              ),
              Text(
                'Auswirkung auf Warenwert: $sign$absAmount $currencyCode (ggü. geplant)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                'MwSt auf Verkauf: $salesVatText $currencyCode (unverändert durch Gebühr)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: baseTextColor),
              ),
              Text(
                'Pot. Vorsteuer-Effekt aus Gebührenabweichung*: $feeTaxSign$feeTaxEffectText $currencyCode',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: baseTextColor),
              ),
              Text(
                '*Informativ: abhängig von der tatsächlichen Buchung der Zahlungsdienstleister-Gebühr.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: baseTextColor),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _isUsdCurrency => _currency.toUpperCase() == 'USD';
  bool get _isNoVatCustomer => _selectedCustomer?.cVat ?? false;

  bool get _isEurCurrency => _currency.toUpperCase() == 'EUR';

  void _syncPriceBasisWithCurrency() {
    if (_isUsdCurrency) {
      _priceBasis = 'net';
    }
  }

  void _syncFxRateWithCurrency({required bool forceUsdReset}) {
    if (_isEurCurrency) {
      final eurRate = _decimalText(1);
      if (_fxToEurController.text != eurRate) {
        _fxToEurController.text = eurRate;
      }
      return;
    }

    if (forceUsdReset || _parseDecimal(_fxToEurController) <= 0) {
      _fxToEurController.text = _decimalText(0);
    }
  }

  void _applyNoVatCustomerRules() {
    if (!_isNoVatCustomer) {
      return;
    }

    _priceBasis = 'net';
  }

  void _setVatRateForPriceBasis() {
    if (_isPuttCashOrder) {
      _vatRateController.text = _decimalText(0);
      return;
    }
    final vatRate = (_priceBasis == 'gross' && !_isNoVatCustomer) ? 19.0 : 0.0;
    _vatRateController.text = _decimalText(vatRate);
  }

  double _assignedItemsGrossTotal() {
    return widget.assignedItems.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalPrice,
    );
  }

  double _assignedItemsTotalWeight() {
    return widget.assignedItems.fold<double>(
      0,
      (sum, item) => sum + item.ioTotalWeight,
    );
  }

  void _refreshTotalWeightFromAssignedItems() {
    if (widget.assignedItems.isEmpty) {
      return;
    }

    final totalWeightText = _weightText(_assignedItemsTotalWeight());
    if (_totalWeightController.text != totalWeightText) {
      _totalWeightController.text = totalWeightText;
    }
  }

  void _refreshGrossGoodsValueFromInputs() {
    final netValue = _parseDecimal(_valueGoodsController);
    final vatRate = _parseDecimal(_vatRateController);
    if (_priceBasis == 'net' && vatRate == 0) {
      const vatValue = 0.0;
      final vatText = _decimalText(vatValue);
      if (_vatController.text != vatText) {
        _vatController.text = vatText;
      }

      final grossText = _decimalText(netValue);
      if (_valueGoodsGrossController.text != grossText) {
        _valueGoodsGrossController.text = grossText;
      }
      return;
    }

    final grossValue = netValue + _parseDecimal(_vatController);
    final formatted = _decimalText(grossValue);
    if (_valueGoodsGrossController.text == formatted) {
      return;
    }
    _valueGoodsGrossController.text = formatted;
  }

  void _refreshGoodsValuesForCurrentBasis() {
    if (_isPuttCashOrder) {
      final grossValue = _assignedItemsGrossTotal();
      final grossText = _decimalText(grossValue);
      final vatText = _decimalText(0);

      if (_valueGoodsGrossController.text != grossText) {
        _valueGoodsGrossController.text = grossText;
      }
      if (_vatController.text != vatText) {
        _vatController.text = vatText;
      }
      if (_valueGoodsController.text != grossText) {
        _valueGoodsController.text = grossText;
      }

      _refreshTotalPriceForCurrentBasis();
      return;
    }

    if (_priceBasis != 'gross') {
      _refreshGrossGoodsValueFromInputs();
      _refreshTotalPriceForCurrentBasis();
      return;
    }

    final grossValue = _assignedItemsGrossTotal();
    final vatRate = _parseDecimal(_vatRateController);
    final divisor = 1 + (vatRate / 100);
    final netValue = divisor <= 0 ? grossValue : grossValue / divisor;
    final vatValue = grossValue - netValue;

    final grossText = _decimalText(grossValue);
    final vatText = _decimalText(vatValue);
    final netText = _decimalText(netValue);

    if (_valueGoodsGrossController.text != grossText) {
      _valueGoodsGrossController.text = grossText;
    }
    if (_vatController.text != vatText) {
      _vatController.text = vatText;
    }
    if (_valueGoodsController.text != netText) {
      _valueGoodsController.text = netText;
    }

    _refreshTotalPriceForCurrentBasis();
  }

  void _refreshTotalPriceForCurrentBasis() {
    if (_isPuttCashOrder) {
      final grossValue = _parseDecimal(_valueGoodsGrossController);
      final totalText = _decimalText(grossValue);
      if (_totalPriceController.text != totalText) {
        _totalPriceController.text = totalText;
      }
      return;
    }

    final grossValue = _parseDecimal(_valueGoodsGrossController);
    final shipping = _parseDecimal(_shippingController);
    final paymentFee = _parseDecimal(_paypalFeeController);
    final total = grossValue + shipping + paymentFee;
    final totalText = _decimalText(total);
    if (_totalPriceController.text != totalText) {
      _totalPriceController.text = totalText;
    }
  }

  void _markPaypalFeeAsManuallyOverridden() {
    if (_isRecalculatingPaypalFee) {
      return;
    }
    _isPaypalFeeManuallyOverridden = true;
  }

  String _deliveryCountryToken() {
    final customer = _selectedCustomer;
    if (customer == null) {
      return '';
    }

    final delivery = (customer.cCountryDId ?? '').trim();
    if (delivery.isNotEmpty && delivery != '-') {
      return delivery.toUpperCase();
    }

    final billing = (customer.cCountryBId ?? '').trim();
    if (billing.isNotEmpty && billing != '-') {
      return billing.toUpperCase();
    }

    return '';
  }

  double? _calculatedPaypalFeeForCurrentInputs() {
    if (_isPuttCashOrder) {
      return null;
    }
    if (_payment != _paypalPaymentCode) {
      return null;
    }

    final goodsGross = _parseDecimal(_valueGoodsGrossController);
    final shipping = _parseDecimal(_shippingController);
    final amountInOrderCurrency = goodsGross + shipping;
    if (amountInOrderCurrency <= 0) {
      return null;
    }

    // PayPal rules are defined in EUR. For USD orders we convert the base amount
    // to EUR, compute the fee, then convert the fee back to USD.
    final fxToEur = _parseDecimal(_fxToEurController);
    final amountInEur = _isEurCurrency
        ? amountInOrderCurrency
        : (fxToEur > 0 ? amountInOrderCurrency * fxToEur : 0.0);
    if (amountInEur <= 0) {
      return null;
    }

    final feeEur = PayPalFeeRules.feeFromNetTargetEur(
      netTargetEur: amountInEur,
      countryToken: _deliveryCountryToken(),
    );
    if (_isEurCurrency) {
      return feeEur;
    }
    if (fxToEur <= 0) {
      return null;
    }
    return feeEur / fxToEur;
  }

  void _recalculatePaypalFeeFromTotalIfApplicable({bool force = false}) {
    if (_isPuttCashOrder) {
      return;
    }
    if (_isRecalculatingPaypalFee) {
      return;
    }
    if (_paypalFeeFocusNode.hasFocus && !force) {
      return;
    }
    if (_payment != _paypalPaymentCode) {
      return;
    }
    if (!force && _isPaypalFeeManuallyOverridden) {
      return;
    }

    final feeInOrderCurrency = _calculatedPaypalFeeForCurrentInputs();
    if (feeInOrderCurrency == null) {
      return;
    }
    final feeText = _decimalText(feeInOrderCurrency);

    if (_paypalFeeController.text == feeText) {
      return;
    }

    _isRecalculatingPaypalFee = true;
    _paypalFeeController.text = feeText;
    _isRecalculatingPaypalFee = false;
  }

  void _recalculatePaypalFeeFromButton() {
    if (_payment != _paypalPaymentCode) {
      return;
    }
    setState(() {
      _isPaypalFeeManuallyOverridden = false;
      _recalculatePaypalFeeFromTotalIfApplicable(force: true);
    });
  }

  String _customerLabel(Customer c) {
    final name = '${c.cLastName}, ${c.cFirstName}'.trim();
    final company = c.cCompany.trim();
    final city = c.cCityB.trim();
    final withCompany =
        company.isEmpty || company == '-' ? name : '$name ($company)';
    return '${c.cId} | $withCompany${city.isEmpty ? '' : ' – $city'}';
  }

  String _normalizeSearchToken(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<Customer> _matchingCustomersFromInput() {
    final input = _normalizeSearchToken(_customerSearchController.text);
    if (input.isEmpty) {
      return const <Customer>[];
    }

    final exactMatches = <Customer>[];
    final partialMatches = <Customer>[];

    for (final customer in widget.allCustomers) {
      final id = _normalizeSearchToken(customer.cId);
      final company = _normalizeSearchToken(customer.cCompany);
      final city = _normalizeSearchToken(customer.cCityB);
      final firstName = _normalizeSearchToken(customer.cFirstName);
      final lastName = _normalizeSearchToken(customer.cLastName);
      final lastFirst = _normalizeSearchToken('${customer.cLastName}, ${customer.cFirstName}');
      final firstLast = _normalizeSearchToken('${customer.cFirstName} ${customer.cLastName}');
      final label = _normalizeSearchToken(_customerLabel(customer));

      final isExact =
          input == id ||
          input == company ||
          input == city ||
          input == firstName ||
          input == lastName ||
          input == lastFirst ||
          input == firstLast ||
          input == label;

      if (isExact) {
        exactMatches.add(customer);
        continue;
      }

      if (id.contains(input) ||
          company.contains(input) ||
          city.contains(input) ||
          firstName.contains(input) ||
          lastName.contains(input) ||
          lastFirst.contains(input) ||
          firstLast.contains(input) ||
          label.contains(input)) {
        partialMatches.add(customer);
      }
    }

    if (exactMatches.isNotEmpty) {
      return exactMatches;
    }
    return partialMatches;
  }

  Customer? _resolveCustomerFromInput() {
    final matches = _matchingCustomersFromInput();
    if (matches.length == 1) {
      return matches.first;
    }
    return null;
  }

  void _filterCustomers(String query) {
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      _filterCustomersNow(query);
    });
  }

  void _filterCustomersNow(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _showCustomerDropdown = q.isNotEmpty;
      if (q.isEmpty) {
        _filteredCustomers = widget.allCustomers;
        return;
      }
      final matches = <Customer>[];
      for (final c in widget.allCustomers) {
        final isMatch = c.cLastName.toLowerCase().contains(q) ||
            c.cFirstName.toLowerCase().contains(q) ||
            c.cCityB.toLowerCase().contains(q) ||
            c.cCompany.toLowerCase().contains(q) ||
            c.cId.toLowerCase().contains(q);
        if (!isMatch) {
          continue;
        }
        matches.add(c);
        if (matches.length >= _maxCustomerSearchResults) {
          break;
        }
      }
      _filteredCustomers = matches;
    });
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _customerSearchController.text = _customerLabel(c);
      _dealer = c.cDealer;
      _syncDeliveryFromSelectedCustomer(force: !_deliveryAddressDifferent);
      _applyNoVatCustomerRules();
      _setVatRateForPriceBasis();
      _refreshGoodsValuesForCurrentBasis();
      _recalculatePaypalFeeFromTotalIfApplicable();
      _showCustomerDropdown = false;
    });
  }

  String _customerFullName(Customer customer) {
    final firstName = customer.cFirstName.trim();
    final lastName = customer.cLastName.trim();
    return '$lastName $firstName'.trim();
  }

  void _openSelectedCustomer() {
    final customerId = _selectedCustomer?.cId.trim() ?? '';
    if (customerId.isEmpty) {
      return;
    }
    Navigator.of(context).pop('open_customer:$customerId');
  }

  String _normalizeCountryId(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty || normalized == '-') {
      return '';
    }
    return normalized;
  }

  String _normalizeCountryForStorage(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '-';
    }
    return normalized;
  }

  String _countryNameForId(String? countryId) {
    final normalizedId = _normalizeCountryId(countryId);
    if (normalizedId.isEmpty) {
      return '';
    }

    for (final country in widget.allCountries) {
      if (country.coTld.toLowerCase() == normalizedId) {
        return country.coName;
      }
    }
    return normalizedId.toUpperCase();
  }

  String _tldToIso(String tld) {
    const mapping = <String, String>{
      'uk': 'gb',
      'ac': 'sh',
      'eu': '',
    };
    return mapping[tld] ?? tld;
  }

  bool _isIsoAlpha2CountryCode(String value) {
    return RegExp(r'^[a-z]{2}$').hasMatch(value);
  }

  void _syncDeliveryFromSelectedCustomer({bool force = false}) {
    final customer = _selectedCustomer;
    if (customer == null) {
      return;
    }
    if (!force && _deliveryAddressDifferent) {
      return;
    }

    _deliveryNameController.text = _customerFullName(customer).isEmpty
        ? '-'
        : _customerFullName(customer);
    _deliveryStreetController.text = customer.cStreetB.trim().isEmpty
        ? '-'
        : customer.cStreetB.trim();
    _deliveryHouseNumberController.text =
        customer.cHouseNumberB.trim().isEmpty ? '-' : customer.cHouseNumberB.trim();
    _deliveryPostalCodeController.text =
        customer.cPostalCodeB.trim().isEmpty ? '-' : customer.cPostalCodeB.trim();
    _deliveryCityController.text =
        customer.cCityB.trim().isEmpty ? '-' : customer.cCityB.trim();
    _deliveryCountryId = _normalizeCountryId(customer.cCountryBId);
    _deliveryCountryController.text = _countryNameForId(_deliveryCountryId);
    _deliveryLatController.text = customer.cLat.toString();
    _deliveryLonController.text = customer.cLon.toString();
  }

  String _normalizeDeliveryField(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '-';
    }
    return trimmed;
  }

  bool _validateDeliveryFieldsIfNeeded() {
    if (!_deliveryAddressDifferent) {
      return true;
    }

    if (_deliveryNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endkunde Name ist erforderlich.')),
      );
      return false;
    }
    if (_deliveryStreetController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lieferadresse Straße ist erforderlich.')),
      );
      return false;
    }
    if (_deliveryHouseNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lieferadresse Hausnummer ist erforderlich.')),
      );
      return false;
    }
    if (_deliveryPostalCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lieferadresse PLZ ist erforderlich.')),
      );
      return false;
    }
    if (_deliveryCityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lieferadresse Stadt ist erforderlich.')),
      );
      return false;
    }
    if (_deliveryCountryId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lieferadresse Land ist erforderlich.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _fetchDeliveryCoordinates({
    bool showFeedbackOnMissingFields = true,
    bool silentNoResult = false,
  }) async {
    final street = _deliveryStreetController.text.trim();
    final houseNumber = _deliveryHouseNumberController.text.trim();
    final postalCode = _deliveryPostalCodeController.text.trim();
    final city = _deliveryCityController.text.trim();

    if (street.isEmpty || postalCode.isEmpty || city.isEmpty) {
      if (showFeedbackOnMissingFields) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Für Koordinaten bitte Straße, PLZ und Stadt ausfüllen.')),
        );
      }
      return;
    }

    final rawCode = _deliveryCountryId.trim().toLowerCase();
    final resolvedCountryCode = _tldToIso(rawCode).trim().toLowerCase();
    final countryCode =
        _isIsoAlpha2CountryCode(resolvedCountryCode) ? resolvedCountryCode : '';

    final query = [
      [street, houseNumber].where((part) => part.isNotEmpty).join(' '),
      [postalCode, city].where((part) => part.isNotEmpty).join(' '),
    ].where((part) => part.isNotEmpty).join(', ');

    setState(() => _isFetchingDeliveryCoordinates = true);
    try {
      final params = <String, String>{
        'q': query,
        'format': 'json',
        'limit': '1',
      };
      if (countryCode.isNotEmpty) {
        params['countrycodes'] = countryCode;
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'arrow_ops/1.0'},
      );

      if (response.statusCode != 200) {
        throw Exception('Nominatim antwortete mit ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        if (!mounted) {
          return;
        }
        if (!silentNoResult) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keine Koordinaten für Lieferadresse gefunden.')),
          );
        }
        return;
      }

      final first = decoded.first;
      if (first is! Map<String, dynamic>) {
        throw Exception('Ungültige Nominatim-Antwort');
      }

      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) {
        throw Exception('Koordinaten konnten nicht gelesen werden');
      }

      _deliveryLatController.text = lat.toString();
      _deliveryLonController.text = lon.toString();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Koordinaten konnten nicht ermittelt werden: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isFetchingDeliveryCoordinates = false);
      }
    }
  }

    void _tryAutoRefreshDeliveryCoordinates() {
      if (_isFetchingDeliveryCoordinates) {
        return;
      }

      final hasAddressData =
          _deliveryStreetController.text.trim().isNotEmpty &&
          _deliveryPostalCodeController.text.trim().isNotEmpty &&
          _deliveryCityController.text.trim().isNotEmpty;

      if (!hasAddressData) {
        return;
      }

      unawaited(
        _fetchDeliveryCoordinates(
          showFeedbackOnMissingFields: false,
          silentNoResult: true,
        ),
      );
    }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    bool readOnly = false,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _row2(Widget a, Widget b) => Row(
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;

    return AlertDialog(
      title: Text(_isEditing ? 'Auftrag bearbeiten' : 'Neuer Auftrag'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: SizedBox(
        width: wide ? 680 : 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Auftrags-ID
                _field(
                  _orderIdController,
                  'Auftrags-ID',
                  focusNode: _orderIdFocusNode,
                  readOnly: _isEditing && !_canEditOrderId,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return 'Auftrags-ID darf nicht leer sein.';
                    }
                    if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                      return 'Format: JJMMTTHHMM';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Hinweis: Format JJMMTTHHMM. Das Bestelldatum wird daraus automatisch abgeleitet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Kundensuche
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _customerSearchController,
                      focusNode: _customerSearchFocusNode,
                      autofocus: !_isEditing,
                      decoration: InputDecoration(
                        labelText: 'Kunde suchen (Name, Vorname, Ort)',
                        border: const OutlineInputBorder(),
                        suffixIcon: _selectedCustomer != null
                            ? IconButton(
                                tooltip: 'Auswahl löschen',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _selectedCustomer = null;
                                    _customerSearchController.clear();
                                    _filteredCustomers = widget.allCustomers;
                                    _showCustomerDropdown = false;
                                  });
                                },
                              )
                            : const Icon(Icons.search),
                      ),
                      validator: (_) => _selectedCustomer == null ? 'Bitte einen Kunden auswählen.' : null,
                      onTap: () => _customerSearchFocusNode.requestFocus(),
                      onChanged: _filterCustomers,
                    ),
                    if (_showCustomerDropdown) ...[
                      const SizedBox(height: 4),
                      Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(4),
                        child: _filteredCustomers.isEmpty
                            ? ListTile(
                                dense: true,
                                title: const Text('Kein Kunde gefunden.'),
                                trailing: TextButton(
                                  onPressed: () => Navigator.of(context).pop('new_customer'),
                                  child: const Text('Neuer Kunde'),
                                ),
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredCustomers.length,
                                  itemBuilder: (context, i) {
                                    final c = _filteredCustomers[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                          '${c.cLastName}, ${c.cFirstName}'),
                                      subtitle: Text(
                                          '${c.cCityB} • ${c.cId}'),
                                      onTap: () => _selectCustomer(c),
                                    );
                                  },
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_selectedCustomer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _openSelectedCustomer,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text('Kunden-ID: ${_selectedCustomer!.cId}'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                SwitchListTile.adaptive(
                  title: const Text('Abweichende Lieferadresse verwenden'),
                  subtitle: const Text(
                    'Wenn deaktiviert, wird die Rechnungsadresse als Lieferadresse übernommen.',
                  ),
                  value: _deliveryAddressDifferent,
                  onChanged: _selectedCustomer == null
                      ? null
                      : (value) {
                          setState(() {
                            _deliveryAddressDifferent = value;
                            if (!value) {
                              _syncDeliveryFromSelectedCustomer(force: true);
                            }
                          });
                        },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),

                if (_deliveryAddressDifferent) ...[
                  DropdownMenu<String>(
                    key: ValueKey('delivery-country-$_deliveryCountryId'),
                    controller: _deliveryCountryController,
                    initialSelection: widget.allCountries.any(
                      (country) => country.coTld.toLowerCase() == _deliveryCountryId,
                    )
                        ? _deliveryCountryId
                        : null,
                    expandedInsets: EdgeInsets.zero,
                    requestFocusOnTap: true,
                    enableFilter: true,
                    enableSearch: true,
                    label: const Text('Lieferadresse Land'),
                    searchCallback: (entries, query) {
                      final normalizedQuery = query.trim().toLowerCase();
                      if (normalizedQuery.isEmpty) {
                        return null;
                      }
                      for (var index = 0; index < entries.length; index++) {
                        final entryLabel = entries[index].label.toLowerCase();
                        if (entryLabel.startsWith(normalizedQuery)) {
                          return index;
                        }
                      }
                      return null;
                    },
                    filterCallback: (entries, query) {
                      final normalizedQuery = query.trim().toLowerCase();
                      if (normalizedQuery.isEmpty) {
                        return entries;
                      }
                      return entries
                          .where(
                            (entry) => entry.label.toLowerCase().startsWith(normalizedQuery),
                          )
                          .toList(growable: false);
                    },
                    dropdownMenuEntries: widget.allCountries
                        .map(
                          (country) => DropdownMenuEntry<String>(
                            value: country.coTld.toLowerCase(),
                            label: '${country.coName} (${country.coTld.toUpperCase()})',
                          ),
                        )
                        .toList(growable: false),
                    onSelected: (value) {
                      setState(() {
                        _deliveryCountryId = _normalizeCountryId(value);
                        _deliveryCountryController.text = _countryNameForId(_deliveryCountryId);
                      });
                      _tryAutoRefreshDeliveryCoordinates();
                    },
                  ),
                  const SizedBox(height: 12),
                  _row2(
                    _field(_deliveryNameController, 'Endkunde Name'),
                    _field(_deliveryCityController, 'Lieferadresse Stadt'),
                  ),
                  const SizedBox(height: 12),
                  _row2(
                    _field(_deliveryStreetController, 'Lieferadresse Straße'),
                    _field(_deliveryHouseNumberController, 'Lieferadresse Hausnummer'),
                  ),
                  const SizedBox(height: 12),
                  _row2(
                    _field(_deliveryPostalCodeController, 'Lieferadresse PLZ'),
                    _field(
                      _deliveryLatController,
                      'Breitengrad (Lat)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _row2(
                    _field(
                      _deliveryLonController,
                      'Längengrad (Lon)',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isFetchingDeliveryCoordinates
                          ? null
                          : _fetchDeliveryCoordinates,
                      icon: _isFetchingDeliveryCoordinates
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.location_searching),
                      label: const Text('Koordinaten ermitteln'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Datum & Währung
                _row2(
                  _field(_dateController, 'Bestelldatum (JJJJ-MM-TT)'),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Währung',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _currency = v ?? 'EUR';
                        _syncFxRateWithCurrency(forceUsdReset: _isUsdCurrency);
                        _syncPriceBasisWithCurrency();
                        _applyNoVatCustomerRules();
                        _setVatRateForPriceBasis();
                        _refreshGoodsValuesForCurrentBasis();
                        _recalculatePaypalFeeFromTotalIfApplicable();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),

                _row2(
                  _field(
                    _fxToEurController,
                    'USD→EUR Kurs',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: _isEurCurrency,
                    validator: (value) {
                      if (_isEurCurrency) {
                        return null;
                      }
                      final parsed = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (parsed == null || parsed <= 0) {
                        return 'Bitte gueltigen USD→EUR Kurs > 0 eingeben.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),

                // ── Sprache & Preisbasis
                _row2(
                  DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: const InputDecoration(
                      labelText: 'Sprache',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'DE', child: Text('DE')),
                      DropdownMenuItem(value: 'EN', child: Text('EN')),
                    ],
                    onChanged: (v) => setState(() => _language = v ?? 'DE'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _priceBasis,
                    decoration: const InputDecoration(
                      labelText: 'Preisart',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'gross', child: Text('Brutto')),
                      DropdownMenuItem(value: 'net', child: Text('Netto')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _priceBasis = _isUsdCurrency ? 'net' : (v ?? 'gross');
                        _applyNoVatCustomerRules();
                        _setVatRateForPriceBasis();
                        _refreshGoodsValuesForCurrentBasis();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // ── MwSt-Satz & Händler
                _row2(
                  _field(
                    _vatRateController,
                    'MwSt-Satz %',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: true,
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Reseller'),
                    value: _dealer,
                    onChanged: null,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Reihenfolge nach Händler
                _row2(
                  _field(
                    _valueGoodsController,
                    'Warenwert netto',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _field(
                    _vatController,
                    'MwSt',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(height: 12),
                _row2(
                  _field(
                    _valueGoodsGrossController,
                    'Warenwert brutto',
                    readOnly: true,
                  ),
                  _field(
                    _shippingController,
                    'Versandkosten',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(height: 12),

                _row2(
                  DropdownButtonFormField<int>(
                    initialValue: _payment,
                    decoration: const InputDecoration(
                      labelText: 'Zahlart',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (int i = 0; i < _paymentLabels.length; i++)
                        DropdownMenuItem(value: i, child: Text(_paymentLabels[i]))
                    ],
                    onChanged: (v) {
                      setState(() {
                        _payment = v ?? 0;
                        if (_payment != _paypalPaymentCode) {
                          _isPaypalFeeManuallyOverridden = false;
                          _paypalFeeController.text = _decimalText(0);
                        } else {
                          _isPaypalFeeManuallyOverridden = false;
                          _recalculatePaypalFeeFromTotalIfApplicable();
                        }

                        _setVatRateForPriceBasis();
                        _refreshGoodsValuesForCurrentBasis();
                      });
                    },
                  ),
                  TextFormField(
                    controller: _paypalFeeController,
                    focusNode: _paypalFeeFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: _payment != _paypalPaymentCode,
                    validator: (value) {
                      if (_payment != _paypalPaymentCode) {
                        return null;
                      }
                      return _validateDecimalFieldValue(value, allowEmpty: false);
                    },
                    decoration: InputDecoration(
                      labelText: 'PayPal-Gebühr',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'PayPal-Gebühr neu berechnen',
                        onPressed: _payment == _paypalPaymentCode
                            ? _recalculatePaypalFeeFromButton
                            : null,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                _row2(
                  DropdownButtonFormField<int?>(
                    initialValue: _paymentActual,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tatsächliche Zahlart (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Geplante verwenden'),
                      ),
                      for (int i = 0; i < _paymentLabels.length; i++)
                        DropdownMenuItem<int?>(value: i, child: Text(_paymentLabels[i]))
                    ],
                    onChanged: (value) {
                      setState(() {
                        _paymentActual = value;
                        if (_paymentActual != null && _paymentActual != _paypalPaymentCode) {
                          _paypalFeeActualController.text = _decimalText(0);
                        }
                      });
                    },
                  ),
                  TextFormField(
                    controller: _paypalFeeActualController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        _validateDecimalFieldValue(value, allowEmpty: true),
                    decoration: const InputDecoration(
                      labelText: 'Tatsächliche PayPal-Gebühr (optional)',
                      border: OutlineInputBorder(),
                      helperText: 'Leer = geplante Gebühr verwenden',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _buildActualSettlementDeltaHint(),
                const SizedBox(height: 12),

                _row2(
                  _field(
                    _totalPriceController,
                    'Gesamtpreis',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    readOnly: true,
                  ),
                  _field(
                    _totalWeightController,
                    'Gesamtgewicht in g',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Bezahldatum & Auslieferungsdatum
                _row2(
                  _field(
                    _payDateController,
                    'Bezahlt-Datum (JJJJ-MM-TT)',
                    keyboardType: TextInputType.datetime,
                    focusNode: _payDateFocusNode,
                  ),
                  _field(
                    _deliveryController,
                    'Versand-Datum (JJJJ-MM-TT)',
                    keyboardType: TextInputType.datetime,
                    focusNode: _deliveryDateFocusNode,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Trackingcode, Trade Show & Putt
                _row2(
                  _field(_trackingCodeController, 'Trackingcode'),
                  _field(_tradeShowController, 'Trade Show'),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  title: const Text('Putt'),
                  value: _putt,
                  onChanged: (value) {
                    setState(() {
                      _putt = value;
                      _setVatRateForPriceBasis();
                      _refreshGoodsValuesForCurrentBasis();
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),

                // ── Notiz
                TextFormField(
                  controller: _noteController,
                  focusNode: _noteFocusNode,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (_selectedCustomer == null) {
              final matches = _matchingCustomersFromInput();
              if (matches.length > 1) {
                setState(() {
                  _filteredCustomers = matches;
                  _showCustomerDropdown = true;
                });
                final examples = matches
                    .take(3)
                    .map((customer) => _customerLabel(customer))
                    .join(', ');
                final suffix = matches.length > 3 ? ' ...' : '';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Mehrere Kunden gefunden (${matches.length}). Bitte eindeutig auswählen, z.B.: $examples$suffix',
                    ),
                  ),
                );
                return;
              }

              final resolvedCustomer = _resolveCustomerFromInput();
              if (resolvedCustomer != null) {
                _selectCustomer(resolvedCustomer);
              }
            }

            if (!_formKey.currentState!.validate()) return;
            if (!_validateDeliveryFieldsIfNeeded()) return;

            if (!_deliveryAddressDifferent) {
              _syncDeliveryFromSelectedCustomer(force: true);
            }

            final result = OrderRow(
              oId: _orderIdController.text.trim(),
              oCustomerId: _selectedCustomer!.cId,
              oDealer: (_selectedCustomer?.cDealer ?? _dealer) ? 1 : 0,
              oDate: _normalizeDateForStorage(_dateController.text),
              oCurrency: _currency,
              oFxToEur: _isEurCurrency ? 1 : _parseDecimal(_fxToEurController),
              oLanguage: _language,
              oPriceBasis: _priceBasis,
              oVatRate: _parseDecimal(_vatRateController),
              oShipping: _parseDecimal(_shippingController),
              oValueGoods: _parseDecimal(_valueGoodsController),
              oTotalPrice: _parseDecimal(_totalPriceController),
              oVat: _parseDecimal(_vatController),
              oTotalWeight: _parseDecimal(_totalWeightController),
              oPayDate: _normalizeDateForStorage(_payDateController.text),
              oPayment: _payment,
              oPaypalFee: _parseDecimal(_paypalFeeController),
              oPaymentActual: _paymentActual,
              oPaypalFeeActual: (() {
                final parsed = _parseOptionalDecimal(_paypalFeeActualController);
                if (parsed != null) {
                  return parsed;
                }
                if (_paymentActual != null && _paymentActual != _paypalPaymentCode) {
                  return 0.0;
                }
                return null;
              })(),
              oDelivery: _normalizeDateForStorage(_deliveryController.text),
              oTradeShow: _tradeShowController.text.trim(),
              oPutt: _putt ? 1 : 0,
              oTrackingCode: _trackingCodeController.text.trim(),
              oNote: _noteController.text.trim().isEmpty ? '-' : _noteController.text.trim(),
                oDeliveryAddressDifferent: _deliveryAddressDifferent ? 1 : 0,
                oDeliveryName: _normalizeDeliveryField(_deliveryNameController.text),
                oDeliveryStreet: _normalizeDeliveryField(_deliveryStreetController.text),
                oDeliveryHouseNumber:
                  _normalizeDeliveryField(_deliveryHouseNumberController.text),
                oDeliveryPostalCode:
                  _normalizeDeliveryField(_deliveryPostalCodeController.text),
                oDeliveryCity: _normalizeDeliveryField(_deliveryCityController.text),
                oDeliveryState: '-',
                oDeliveryCountryId: _normalizeCountryForStorage(_deliveryCountryId),
                oDeliveryLat:
                  double.tryParse(_deliveryLatController.text.trim().replaceAll(',', '.')) ?? 0,
                oDeliveryLon:
                  double.tryParse(_deliveryLonController.text.trim().replaceAll(',', '.')) ?? 0,
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
