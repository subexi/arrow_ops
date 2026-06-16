import 'package:flutter/material.dart';

import '../../../customer/domain/customer.dart';
import '../../../order/domain/order_models.dart';
import '../../domain/paypal_fee_rules.dart';

class OrderFormDialog extends StatefulWidget {
  const OrderFormDialog({
    super.key,
    required this.allCustomers,
    this.initialValue,
    this.canEditOrderId = true,
    this.assignedItems = const [],
  });

  final List<Customer> allCustomers;
  final OrderRow? initialValue;
  final bool canEditOrderId;
  final List<ItemOrderedRow> assignedItems;

  @override
  State<OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends State<OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteFocusNode = FocusNode();
  final _paypalFeeFocusNode = FocusNode();

  late final TextEditingController _orderIdController;
  late final TextEditingController _customerSearchController;
  late final TextEditingController _dateController;
  late final TextEditingController _vatRateController;
  late final TextEditingController _shippingController;
  late final TextEditingController _valueGoodsController;
  late final TextEditingController _valueGoodsGrossController;
  late final TextEditingController _totalPriceController;
  late final TextEditingController _vatController;
  late final TextEditingController _totalWeightController;
  late final TextEditingController _payDateController;
  late final TextEditingController _paypalFeeController;
  late final TextEditingController _deliveryController;
  late final TextEditingController _trackingCodeController;
  late final TextEditingController _noteController;

  Customer? _selectedCustomer;
  String _currency = 'EUR';
  String _language = 'DE';
  String _priceBasis = 'gross';
  int _payment = 0;
  bool _dealer = false;
  List<Customer> _filteredCustomers = [];
  bool _showCustomerDropdown = false;
  bool _isRecalculatingPaypalFee = false;

  static const int _paypalPaymentCode = 1;

  bool get _isEditing => widget.initialValue != null;
  bool get _canEditOrderId => !_isEditing || widget.canEditOrderId;

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
    _vatRateController = TextEditingController(text: _decimalText(v?.oVatRate ?? 19));
    _shippingController = TextEditingController(text: _decimalText(v?.oShipping ?? 0));
    _valueGoodsController = TextEditingController(text: _decimalText(v?.oValueGoods ?? 0));
    _valueGoodsGrossController = TextEditingController();
    _totalPriceController = TextEditingController(text: _decimalText(v?.oTotalPrice ?? 0));
    _vatController = TextEditingController(text: _decimalText(v?.oVat ?? 0));
    _totalWeightController = TextEditingController(text: _weightText(v?.oTotalWeight ?? 0));
    _payDateController = TextEditingController(text: v?.oPayDate ?? '');
    _paypalFeeController = TextEditingController(text: _decimalText(v?.oPaypalFee ?? 0));
    _deliveryController = TextEditingController(text: v?.oDelivery ?? '');
    _trackingCodeController = TextEditingController(text: v?.oTrackingCode ?? '');
    _noteController = TextEditingController(text: v?.oNote ?? '-');

    _currency = v?.oCurrency ?? 'EUR';
    _language = v?.oLanguage ?? 'DE';
    _priceBasis = v?.oPriceBasis ?? 'gross';
    _payment = v?.oPayment ?? _paypalPaymentCode;
    _dealer = (v?.oDealer ?? 0) != 0;

    _syncPriceBasisWithCurrency();
    _setVatRateForPriceBasis();
    _refreshTotalWeightFromAssignedItems();
    _refreshGoodsValuesForCurrentBasis();
    _valueGoodsController.addListener(_refreshGoodsValuesForCurrentBasis);
    _vatController.addListener(_refreshGoodsValuesForCurrentBasis);
    _vatRateController.addListener(_refreshGoodsValuesForCurrentBasis);
    _shippingController.addListener(_refreshTotalPriceForCurrentBasis);
    _paypalFeeController.addListener(_refreshTotalPriceForCurrentBasis);
    _totalPriceController.addListener(_recalculatePaypalFeeFromTotalIfApplicable);
    _noteFocusNode.addListener(_clearNotePlaceholderOnFocus);

    if (v != null) {
      final existing = widget.allCustomers.cast<Customer?>().firstWhere(
            (c) => c?.cId == v.oCustomerId,
            orElse: () => null,
          );
      _selectedCustomer = existing;
      if (existing != null) {
        _customerSearchController.text = _customerLabel(existing);
        _dealer = existing.cDealer;
        _applyNoVatCustomerRules();
        _setVatRateForPriceBasis();
        _refreshGoodsValuesForCurrentBasis();
        _recalculatePaypalFeeFromTotalIfApplicable();
      }
    }

    _filteredCustomers = widget.allCustomers;
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    _customerSearchController.dispose();
    _dateController.dispose();
    _vatRateController.dispose();
    _shippingController.dispose();
    _valueGoodsController.dispose();
    _valueGoodsGrossController.dispose();
    _totalPriceController.dispose();
    _vatController.dispose();
    _totalWeightController.dispose();
    _payDateController.dispose();
    _paypalFeeController.dispose();
    _deliveryController.dispose();
    _trackingCodeController.dispose();
    _noteController.dispose();
    _paypalFeeFocusNode.dispose();
    _noteFocusNode.dispose();
    super.dispose();
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

  double _parseDecimal(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  bool get _isUsdCurrency => _currency.toUpperCase() == 'USD';
  bool get _isNoVatCustomer => _selectedCustomer?.cVat ?? false;

  bool get _isEurCurrency => _currency.toUpperCase() == 'EUR';

  void _syncPriceBasisWithCurrency() {
    if (_isUsdCurrency) {
      _priceBasis = 'net';
    }
  }

  void _applyNoVatCustomerRules() {
    if (!_isNoVatCustomer) {
      return;
    }

    _priceBasis = 'net';
  }

  void _setVatRateForPriceBasis() {
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
    final grossValue = _parseDecimal(_valueGoodsGrossController);
    final shipping = _parseDecimal(_shippingController);
    final paymentFee = _parseDecimal(_paypalFeeController);
    final total = grossValue + shipping + paymentFee;
    final totalText = _decimalText(total);
    if (_totalPriceController.text != totalText) {
      _totalPriceController.text = totalText;
    }
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

  void _recalculatePaypalFeeFromTotalIfApplicable() {
    if (_isRecalculatingPaypalFee) {
      return;
    }
    if (_paypalFeeFocusNode.hasFocus) {
      return;
    }
    if (_payment != _paypalPaymentCode || !_isEurCurrency) {
      return;
    }

    final existingFee = _parseDecimal(_paypalFeeController);
    if (existingFee != 0) {
      return;
    }

    final goodsGross = _parseDecimal(_valueGoodsGrossController);
    final shipping = _parseDecimal(_shippingController);
    final feeBase = goodsGross + shipping;
    if (feeBase <= 0) {
      return;
    }

    final fee = PayPalFeeRules.feeFromBaseAmountEur(
      baseAmountEur: feeBase,
      countryToken: _deliveryCountryToken(),
    );
    final feeText = _decimalText(fee);

    if (_paypalFeeController.text == feeText) {
      return;
    }

    _isRecalculatingPaypalFee = true;
    _paypalFeeController.text = feeText;
    _isRecalculatingPaypalFee = false;
  }

  String _customerLabel(Customer c) {
    final name = '${c.cLastName}, ${c.cFirstName}'.trim();
    final company = c.cCompany.trim();
    final city = c.cCityB.trim();
    final withCompany =
        company.isEmpty || company == '-' ? name : '$name ($company)';
    return '$withCompany${city.isEmpty ? '' : ' – $city'}';
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
    final q = query.trim().toLowerCase();
    setState(() {
      _showCustomerDropdown = q.isNotEmpty;
      if (q.isEmpty) {
        _filteredCustomers = widget.allCustomers;
        return;
      }
      _filteredCustomers = widget.allCustomers.where((c) {
        return c.cLastName.toLowerCase().contains(q) ||
            c.cFirstName.toLowerCase().contains(q) ||
            c.cCityB.toLowerCase().contains(q) ||
            c.cCompany.toLowerCase().contains(q) ||
            c.cId.toLowerCase().contains(q);
      }).toList(growable: false);
    });
  }

  void _selectCustomer(Customer c) {
    setState(() {
      _selectedCustomer = c;
      _customerSearchController.text = _customerLabel(c);
      _dealer = c.cDealer;
      _applyNoVatCustomerRules();
      _setVatRateForPriceBasis();
      _refreshGoodsValuesForCurrentBasis();
      _recalculatePaypalFeeFromTotalIfApplicable();
      _showCustomerDropdown = false;
    });
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
                  readOnly: !_canEditOrderId,
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
                const SizedBox(height: 12),

                // ── Kundensuche
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _customerSearchController,
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
                        child: Text(
                          'Kunden-ID: ${_selectedCustomer!.cId}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

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
                          _paypalFeeController.text = _decimalText(0);
                        } else {
                          _recalculatePaypalFeeFromTotalIfApplicable();
                        }
                      });
                    },
                  ),
                  _field(
                    _paypalFeeController,
                    'PayPal-Gebühr',
                    focusNode: _paypalFeeFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
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
                  _field(_payDateController, 'Bezahldatum (JJJJ-MM-TT)'),
                  _field(_deliveryController, 'Auslieferungsdatum (JJJJ-MM-TT)'),
                ),
                const SizedBox(height: 12),

                // ── Trackingcode
                _field(_trackingCodeController, 'Trackingcode'),
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
            final result = OrderRow(
              oId: _orderIdController.text.trim(),
              oCustomerId: _selectedCustomer!.cId,
              oDealer: (_selectedCustomer?.cDealer ?? _dealer) ? 1 : 0,
              oDate: _normalizeDateForStorage(_dateController.text),
              oCurrency: _currency,
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
              oDelivery: _normalizeDateForStorage(_deliveryController.text),
              oTrackingCode: _trackingCodeController.text.trim(),
              oNote: _noteController.text.trim().isEmpty ? '-' : _noteController.text.trim(),
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
