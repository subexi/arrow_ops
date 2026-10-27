import 'package:flutter/material.dart';

import '../../domain/incoming_invoice_row.dart';

enum _CalculationBasis { gross, net }

class IncomingInvoiceFormDialog extends StatefulWidget {
  const IncomingInvoiceFormDialog({
    super.key,
    required this.nextId,
    required this.nameOptions,
    required this.usageOptions,
    required this.kat1Options,
    required this.kat2Options,
    required this.countryOptions,
    this.initialValue,
  });

  final int nextId;
  final List<String> nameOptions;
  final List<String> usageOptions;
  final List<String> kat1Options;
  final List<String> kat2Options;
  final List<String> countryOptions;
  final IncomingInvoiceRow? initialValue;

  @override
  State<IncomingInvoiceFormDialog> createState() => _IncomingInvoiceFormDialogState();
}

class _IncomingInvoiceFormDialogState extends State<IncomingInvoiceFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _dateController;
  late final TextEditingController _grossController;
  late final TextEditingController _vatRateController;
  late final TextEditingController _netController;
  late final TextEditingController _vatController;

  late List<String> _nameOptions;
  late List<String> _usageOptions;
  late List<String> _kat1Options;
  late List<String> _kat2Options;
  late List<String> _countryOptions;

  late String _nameValue;
  late String _usageValue;
  late String _kat1Value;
  late String _kat2Value;
  late String _countryValue;
  _CalculationBasis _lastCalculationBasis = _CalculationBasis.gross;
  bool _isAutoUpdatingAmounts = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameOptions = _withInitial(widget.nameOptions, initial?.riName);
    _usageOptions = _withInitial(widget.usageOptions, initial?.riUsage);
    _kat1Options = _withInitial(widget.kat1Options, initial?.riKat1);
    _kat2Options = _withInitial(widget.kat2Options, initial?.riKat2);
    _countryOptions = _withInitial(widget.countryOptions, initial?.riCountry);

    _nameValue = _selectInitial(initial?.riName, _nameOptions);
    _usageValue = _selectInitial(initial?.riUsage, _usageOptions);
    _kat1Value = _selectInitial(initial?.riKat1, _kat1Options);
    _kat2Value = _selectInitial(initial?.riKat2, _kat2Options);
    _countryValue = _selectInitial(initial?.riCountry, _countryOptions);

    _dateController = TextEditingController(
      text: initial?.riDate.isNotEmpty == true
          ? initial!.riDate
          : _todayIsoDate(),
    );
    _grossController = TextEditingController(text: _decimalText(initial?.riGross));
    _vatRateController = TextEditingController(text: _decimalText(initial?.riVatRate));
    _netController = TextEditingController(text: _decimalText(initial?.riNet));
    _vatController = TextEditingController(text: _decimalText(initial?.riVat));
    if ((initial?.riNet ?? 0) != 0 && (initial?.riGross ?? 0) == 0) {
      _lastCalculationBasis = _CalculationBasis.net;
    }
    _grossController.addListener(_onGrossChanged);
    _netController.addListener(_onNetChanged);
    _vatRateController.addListener(_onVatRateChanged);
    _recalculateAmounts();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _grossController.dispose();
    _vatRateController.dispose();
    _netController.dispose();
    _vatController.dispose();
    super.dispose();
  }

  static String _todayIsoDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String _decimalText(double? value) {
    if (value == null) {
      return '';
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  static List<String> _withInitial(List<String> options, String? initial) {
    final normalizedInitial = initial?.trim() ?? '';
    final set = <String>{
      for (final value in options)
        if (value.trim().isNotEmpty) value.trim(),
    };
    if (normalizedInitial.isNotEmpty) {
      set.add(normalizedInitial);
    }
    final result = set.toList(growable: false);
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  static String _selectInitial(String? initial, List<String> options) {
    final value = initial?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
    if (options.isNotEmpty) {
      return options.first;
    }
    return '';
  }

  void _onGrossChanged() {
    if (_isAutoUpdatingAmounts) {
      return;
    }
    if (mounted) {
      setState(() {
        _lastCalculationBasis = _CalculationBasis.gross;
      });
    } else {
      _lastCalculationBasis = _CalculationBasis.gross;
    }
    _recalculateAmounts();
  }

  void _onNetChanged() {
    if (_isAutoUpdatingAmounts) {
      return;
    }
    if (mounted) {
      setState(() {
        _lastCalculationBasis = _CalculationBasis.net;
      });
    } else {
      _lastCalculationBasis = _CalculationBasis.net;
    }
    _recalculateAmounts();
  }

  void _onVatRateChanged() {
    if (_isAutoUpdatingAmounts) {
      return;
    }
    _recalculateAmounts();
  }

  void _recalculateAmounts() {
    final vatRate = _parseDouble(_vatRateController.text);
    final divisor = 1 + (vatRate / 100);
    final grossInput = _parseDouble(_grossController.text);
    final netInput = _parseDouble(_netController.text);
    late final double gross;
    late final double net;

    if (_lastCalculationBasis == _CalculationBasis.net) {
      net = netInput;
      gross = net * divisor;
    } else {
      gross = grossInput;
      net = divisor == 0 ? 0 : gross / divisor;
    }
    final vat = gross - net;

    _isAutoUpdatingAmounts = true;
    try {
      if (_lastCalculationBasis == _CalculationBasis.net) {
        _grossController.text = gross.toStringAsFixed(2).replaceAll('.', ',');
      } else {
        _netController.text = net.toStringAsFixed(2).replaceAll('.', ',');
      }
      _vatController.text = vat.toStringAsFixed(2).replaceAll('.', ',');
    } finally {
      _isAutoUpdatingAmounts = false;
    }
  }

  double _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String? _validateDate(String? value) {
    final dateText = value?.trim() ?? '';
    if (dateText.isEmpty) {
      return 'Datum ist erforderlich';
    }
    if (DateTime.tryParse(dateText) == null) {
      return 'Datum muss im Format YYYY-MM-DD sein';
    }
    return null;
  }

  String? _validateRequiredSelection(String value, String label) {
    if (value.trim().isEmpty) {
      return '$label ist erforderlich';
    }
    return null;
  }

  String get _calculationHintText {
    if (_lastCalculationBasis == _CalculationBasis.net) {
      return 'Aktive Basis: Netto → Brutto und MwSt werden berechnet';
    }
    return 'Aktive Basis: Brutto → Netto und MwSt werden berechnet';
  }

  String get _grossLabel {
    return _lastCalculationBasis == _CalculationBasis.gross
        ? 'Brutto (aktiv)'
        : 'Brutto';
  }

  String get _netLabel {
    return _lastCalculationBasis == _CalculationBasis.net
        ? 'Netto (aktiv)'
        : 'Netto';
  }

  Widget _dropdownField({
    required String label,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    if (options.isEmpty) {
      return TextFormField(
        initialValue: currentValue,
        decoration: InputDecoration(
          labelText: '$label (neu)',
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
        validator: (value) => _validateRequiredSelection(value ?? '', label),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: currentValue.isEmpty ? null : currentValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value == null) {
          return;
        }
        onChanged(value);
      },
      validator: (_) => _validateRequiredSelection(currentValue, label),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final gross = _parseDouble(_grossController.text);
    final vatRate = _parseDouble(_vatRateController.text);
    final net = _parseDouble(_netController.text);
    final vat = _parseDouble(_vatController.text);

    Navigator.of(context).pop(
      IncomingInvoiceRow(
        riId: widget.initialValue?.riId ?? widget.nextId,
        riDate: _dateController.text.trim(),
        riName: _nameValue.trim(),
        riUsage: _usageValue.trim(),
        riKat1: _kat1Value.trim(),
        riKat2: _kat2Value.trim(),
        riCountry: _countryValue.trim(),
        riGross: gross,
        riVatRate: vatRate,
        riNet: net,
        riVat: vat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialValue == null
            ? 'Rechnungseingang anlegen'
            : 'Rechnungseingang bearbeiten',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: 'Datum',
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateDate,
                ),
                const SizedBox(height: 12),
                _dropdownField(
                  label: 'Name',
                  options: _nameOptions,
                  currentValue: _nameValue,
                  onChanged: (value) => setState(() => _nameValue = value),
                ),
                const SizedBox(height: 12),
                _dropdownField(
                  label: 'Verwendung',
                  options: _usageOptions,
                  currentValue: _usageValue,
                  onChanged: (value) => setState(() => _usageValue = value),
                ),
                const SizedBox(height: 12),
                _dropdownField(
                  label: 'Kat1',
                  options: _kat1Options,
                  currentValue: _kat1Value,
                  onChanged: (value) => setState(() => _kat1Value = value),
                ),
                const SizedBox(height: 12),
                _dropdownField(
                  label: 'Kat2',
                  options: _kat2Options,
                  currentValue: _kat2Value,
                  onChanged: (value) => setState(() => _kat2Value = value),
                ),
                const SizedBox(height: 12),
                _dropdownField(
                  label: 'Land',
                  options: _countryOptions,
                  currentValue: _countryValue,
                  onChanged: (value) => setState(() => _countryValue = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _grossController,
                  decoration: InputDecoration(
                    labelText: _grossLabel,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vatRateController,
                  decoration: const InputDecoration(
                    labelText: 'MwSt-Satz (%)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calculate_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _calculationHintText,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _netController,
                  decoration: InputDecoration(
                    labelText: _netLabel,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vatController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'MwSt',
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
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

}
