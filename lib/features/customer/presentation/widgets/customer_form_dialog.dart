import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/country_tld.dart';
import '../../domain/customer.dart';

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    super.key,
    this.customer,
    this.countries = const [],
  });

  final Customer? customer;
  final List<CountryTld> countries;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  late final TextEditingController _idControl;
  late final TextEditingController _lastNameControl;
  late final TextEditingController _firstNameControl;
  late final TextEditingController _companyControl;
  late final TextEditingController _vatIdControl;
  late final TextEditingController _careofBControl;
  late final TextEditingController _streetBControl;
  late final TextEditingController _houseNumberBControl;
  late final TextEditingController _postalCodeBControl;
  late final TextEditingController _cityBControl;
  late final TextEditingController _stateBControl;
  late final TextEditingController _careofDControl;
  late final TextEditingController _streetDControl;
  late final TextEditingController _houseNumberDControl;
  late final TextEditingController _postalCodeDControl;
  late final TextEditingController _cityDControl;
  late final TextEditingController _stateDControl;
  late final TextEditingController _mailControl;
  late final TextEditingController _phoneControl;
  late final TextEditingController _webControl;
  late final TextEditingController _socialMediaControl;
  late final TextEditingController _latControl;
  late final TextEditingController _longControl;
  late final TextEditingController _noteControl;
  late final TextEditingController _countryBControl;
  late final TextEditingController _countryDControl;
  late final FocusNode _careofBFocusNode;
  late final FocusNode _streetBFocusNode;
  late final FocusNode _houseNumberBFocusNode;
  late final FocusNode _postalCodeBFocusNode;
  late final FocusNode _cityBFocusNode;
  late final FocusNode _stateBFocusNode;

  String? _countryBId;
  String? _countryDId;
  late bool _dealer;
  late bool _vat;
  late bool _isEditing;

  String? _defaultCountryId() {
    for (final country in widget.countries) {
      if (country.coTld.toLowerCase() == 'de') {
        return country.coTld;
      }
    }
    for (final country in widget.countries) {
      final name = country.coName.toLowerCase();
      if (name == 'germany' || name == 'deutschland') {
        return country.coTld;
      }
    }
    return null;
  }

  String _countryNameForId(String? countryId) {
    if (countryId == null) {
      return '';
    }
    for (final country in widget.countries) {
      if (country.coTld.toLowerCase() == countryId.toLowerCase()) {
        return country.coName;
      }
    }
    return '';
  }

  void _syncOnBlur({
    required FocusNode focusNode,
    required TextEditingController source,
    required TextEditingController target,
  }) {
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        target.text = source.text;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _isEditing = c != null;
    _idControl = TextEditingController(text: c?.cId ?? '');
    _lastNameControl = TextEditingController(text: c?.cLastName.toUpperCase() ?? '');
    _firstNameControl = TextEditingController(text: c?.cFirstName ?? '');
    _companyControl = TextEditingController(text: c?.cCompany ?? '-');
    _vatIdControl = TextEditingController(text: c?.cVatId ?? '-');
    _careofBControl = TextEditingController(text: c?.cCareofB ?? '-');
    _streetBControl = TextEditingController(text: c?.cStreetB ?? '');
    _houseNumberBControl = TextEditingController(text: c?.cHouseNumberB ?? '');
    _postalCodeBControl = TextEditingController(text: c?.cPostalCodeB ?? '');
    _cityBControl = TextEditingController(text: c?.cCityB ?? '');
    _stateBControl = TextEditingController(text: c?.cStateB ?? '-');
    _countryBId = c?.cCountryBId?.toLowerCase() ?? _defaultCountryId();
    _countryBControl = TextEditingController(text: _countryNameForId(_countryBId));
    _streetDControl = TextEditingController(text: c?.cStreetD ?? _streetBControl.text);
    _houseNumberDControl = TextEditingController(text: c?.cHouseNumberD ?? _houseNumberBControl.text);
    _postalCodeDControl = TextEditingController(text: c?.cPostalCodeD ?? _postalCodeBControl.text);
    _cityDControl = TextEditingController(text: c?.cCityD ?? _cityBControl.text);
    _careofDControl = TextEditingController(text: c?.cCareofD ?? _careofBControl.text);
    _stateDControl = TextEditingController(text: c?.cStateD ?? _stateBControl.text);
    _countryDId = c?.cCountryDId?.toLowerCase() ?? _countryBId;
    _countryDControl = TextEditingController(text: _countryNameForId(_countryDId));
    _mailControl = TextEditingController(text: c?.cMail ?? '-');
    _phoneControl = TextEditingController(text: c?.cPhone ?? '-');
    _webControl = TextEditingController(text: c?.cWeb ?? '-');
    _socialMediaControl = TextEditingController(text: c?.cSocialMedia ?? '-');
    _latControl = TextEditingController(text: c != null ? c.cLat.toString() : '0');
    _longControl = TextEditingController(text: c != null ? c.cLong.toString() : '0');
    _noteControl = TextEditingController(text: c?.cNote ?? '-');
    _dealer = c?.cDealer ?? false;
    _vat = c?.cVat ?? false;

    _careofBFocusNode = FocusNode();
    _streetBFocusNode = FocusNode();
    _houseNumberBFocusNode = FocusNode();
    _postalCodeBFocusNode = FocusNode();
    _cityBFocusNode = FocusNode();
    _stateBFocusNode = FocusNode();

    _syncOnBlur(
      focusNode: _careofBFocusNode,
      source: _careofBControl,
      target: _careofDControl,
    );
    _syncOnBlur(
      focusNode: _streetBFocusNode,
      source: _streetBControl,
      target: _streetDControl,
    );
    _syncOnBlur(
      focusNode: _houseNumberBFocusNode,
      source: _houseNumberBControl,
      target: _houseNumberDControl,
    );
    _syncOnBlur(
      focusNode: _postalCodeBFocusNode,
      source: _postalCodeBControl,
      target: _postalCodeDControl,
    );
    _syncOnBlur(
      focusNode: _cityBFocusNode,
      source: _cityBControl,
      target: _cityDControl,
    );
    _syncOnBlur(
      focusNode: _stateBFocusNode,
      source: _stateBControl,
      target: _stateDControl,
    );
  }

  @override
  void dispose() {
    _idControl.dispose();
    _lastNameControl.dispose();
    _firstNameControl.dispose();
    _companyControl.dispose();
    _vatIdControl.dispose();
    _careofBControl.dispose();
    _streetBControl.dispose();
    _houseNumberBControl.dispose();
    _postalCodeBControl.dispose();
    _cityBControl.dispose();
    _stateBControl.dispose();
    _streetDControl.dispose();
    _houseNumberDControl.dispose();
    _postalCodeDControl.dispose();
    _cityDControl.dispose();
    _careofDControl.dispose();
    _stateDControl.dispose();
    _mailControl.dispose();
    _phoneControl.dispose();
    _webControl.dispose();
    _socialMediaControl.dispose();
    _latControl.dispose();
    _longControl.dispose();
    _noteControl.dispose();
    _countryBControl.dispose();
    _countryDControl.dispose();
    _careofBFocusNode.dispose();
    _streetBFocusNode.dispose();
    _houseNumberBFocusNode.dispose();
    _postalCodeBFocusNode.dispose();
    _cityBFocusNode.dispose();
    _stateBFocusNode.dispose();
    super.dispose();
  }

  String? _validateId(String cId) {
    if (cId.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cId)) {
      return 'The Customer-ID must have exactly 10 digits.';
    }

    final year = int.parse(cId.substring(0, 2));
    final month = int.parse(cId.substring(2, 4));
    final day = int.parse(cId.substring(4, 6));
    final hour = int.parse(cId.substring(6, 8));
    final minute = int.parse(cId.substring(8, 10));
    final currentYear = DateTime.now().year % 100;

    if (year < 0 || year > currentYear) {
      return 'The first 2 digits of the Customer-ID must be between 00 and $currentYear.';
    }
    if (month < 1 || month > 12) {
      return 'The 3rd and 4th digit of the Customer-ID must be between 01 and 12.';
    }
    if (day < 1 || day > 31) {
      return 'The 5th and 6th digit of the Customer-ID must be between 01 and 31.';
    }
    if (hour < 0 || hour > 23) {
      return 'The 7th and 8th digit of the Customer-ID must be between 00 and 23.';
    }
    if (minute < 0 || minute > 59) {
      return 'The 9th and 10th digit of the Customer-ID must be between 00 and 59.';
    }

    final date = DateTime(2000 + year, month, day);
    if (date.month != month || date.day != day) {
      return 'The Customer-ID is not valid.';
    }

    return null;
  }

  bool _isGermany(String? countryId) {
    return countryId?.trim().toLowerCase() == 'de';
  }

  Future<String?> _resolveGermanState(String postalCode) async {
    final normalizedPostalCode = postalCode.trim();
    if (normalizedPostalCode.isEmpty) {
      return null;
    }

    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.rawQuery(
        'SELECT state_short, state FROM postal_code_de WHERE postal_code = ? LIMIT 1',
        [normalizedPostalCode],
      );
      if (rows.isEmpty) {
        return null;
      }

      final row = rows.first;
      final state = (row['state']?.toString().trim() ?? '');
      final stateShort = (row['state_short']?.toString().trim() ?? '');

      if (state.isEmpty && stateShort.isEmpty) {
        return null;
      }
      if (stateShort.isEmpty) {
        return state;
      }
      if (state.isEmpty) {
        return stateShort;
      }
      return '$stateShort - $state';
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateStateFromCountryAndPostalCode({required bool billing}) async {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isGermany(countryId)) {
      return;
    }

    final postalCode = billing ? _postalCodeBControl.text : _postalCodeDControl.text;
    final resolvedState = await _resolveGermanState(postalCode);
    if (!mounted || resolvedState == null || resolvedState.isEmpty) {
      return;
    }

    setState(() {
      if (billing) {
        _stateBControl.text = resolvedState;
      } else {
        _stateDControl.text = resolvedState;
      }
    });
  }

  Future<bool> _validateForm() async {
    final messenger = ScaffoldMessenger.of(context);
    final cId = _idControl.text.trim();
    final idValidationError = _validateId(cId);
    if (idValidationError != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(idValidationError)),
      );
      return false;
    }
    if (_firstNameControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vorname erforderlich')),
      );
      return false;
    }
    if (!_firstNameControl.text.trim().replaceAll(' ', '').split('').every((c) => RegExp(r'[a-zA-ZÀ-ÖØ-öø-ÿ]').hasMatch(c))) {
      messenger.showSnackBar(
        const SnackBar(content: Text('First Name must contain only letters and spaces.')),
      );
      return false;
    }
    if (_lastNameControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nachname erforderlich')),
      );
      return false;
    }
    if (!_lastNameControl.text.trim().replaceAll(' ', '').split('').every((c) => RegExp(r'[a-zA-ZÀ-ÖØ-öø-ÿ]').hasMatch(c))) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Last Name must contain only letters and spaces.')),
      );
      return false;
    }
    if (_streetBControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Straße (Rechnungsadresse) erforderlich')),
      );
      return false;
    }
    if (_streetBControl.text.trim().length < 2) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Too short for a street name.')),
      );
      return false;
    }
    if (_postalCodeBControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PLZ (Rechnungsadresse) erforderlich')),
      );
      return false;
    }
    if (_cityBControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Stadt (Rechnungsadresse) erforderlich')),
      );
      return false;
    }
    {
      final city = _cityBControl.text.trim();
      final stripped = city.replaceAll(' ', '').replaceAll('-', '');
      if (city.length < 2 || !RegExp(r'^[\p{L}]+$', unicode: true).hasMatch(stripped)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Stadt (Rechnungsadresse) must contain at least 2 letters and only alphabetic characters.')),
        );
        return false;
      }
    }
    if (_countryBId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Land (Rechnungsadresse) erforderlich')),
      );
      return false;
    }
    if (_isGermany(_countryBId)) {
      final billingState = await _resolveGermanState(_postalCodeBControl.text);
      if (billingState == null) {
        if (!mounted) {
          return false;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('Please enter a valid postal code for the Rechnungsadresse.')),
        );
        return false;
      }
      _stateBControl.text = billingState;
    }
    if (_streetDControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Straße (Lieferadresse) erforderlich')),
      );
      return false;
    }
    if (_postalCodeDControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PLZ (Lieferadresse) erforderlich')),
      );
      return false;
    }
    if (_cityDControl.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Stadt (Lieferadresse) erforderlich')),
      );
      return false;
    }
    {
      final city = _cityDControl.text.trim();
      final stripped = city.replaceAll(' ', '').replaceAll('-', '');
      if (city.length < 2 || !RegExp(r'^[\p{L}]+$', unicode: true).hasMatch(stripped)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Stadt (Lieferadresse) must contain at least 2 letters and only alphabetic characters.')),
        );
        return false;
      }
    }
    if (_countryDId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Land (Lieferadresse) erforderlich')),
      );
      return false;
    }
    if (_isGermany(_countryDId)) {
      final deliveryState = await _resolveGermanState(_postalCodeDControl.text);
      if (deliveryState == null) {
        if (!mounted) {
          return false;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('Please enter a valid postal code for the Lieferadresse.')),
        );
        return false;
      }
      _stateDControl.text = deliveryState;
    }
    return true;
  }

  Customer _buildCustomer() {
    final lastName = _lastNameControl.text.trim().toUpperCase();

    return Customer(
      cId: _idControl.text.trim(),
      cLastName: lastName,
      cFirstName: _firstNameControl.text.trim(),
      cCompany: _companyControl.text.trim().isEmpty ? '-' : _companyControl.text.trim(),
      cDealer: _dealer,
      cVat: _vat,
      cVatId: _vatIdControl.text.trim().isEmpty ? '-' : _vatIdControl.text.trim(),
      cCareofB: _careofBControl.text.trim().isEmpty ? '-' : _careofBControl.text.trim(),
      cStreetB: _streetBControl.text.trim(),
      cHouseNumberB: _houseNumberBControl.text.trim(),
      cPostalCodeB: _postalCodeBControl.text.trim(),
      cCityB: _cityBControl.text.trim(),
      cStateB: _stateBControl.text.trim().isEmpty ? '-' : _stateBControl.text.trim(),
      cCountryBId: _countryBId,
      cCareofD: _careofDControl.text.trim().isEmpty ? '-' : _careofDControl.text.trim(),
      cStreetD: _streetDControl.text.trim(),
      cHouseNumberD: _houseNumberDControl.text.trim(),
      cPostalCodeD: _postalCodeDControl.text.trim(),
      cCityD: _cityDControl.text.trim(),
      cStateD: _stateDControl.text.trim().isEmpty ? '-' : _stateDControl.text.trim(),
      cCountryDId: _countryDId,
      cMail: _mailControl.text.trim().isEmpty ? '-' : _mailControl.text.trim(),
      cPhone: _phoneControl.text.trim().isEmpty ? '-' : _phoneControl.text.trim(),
      cWeb: _webControl.text.trim().isEmpty ? '-' : _webControl.text.trim(),
      cSocialMedia: _socialMediaControl.text.trim().isEmpty ? '-' : _socialMediaControl.text.trim(),
      cLat: double.tryParse(_latControl.text.trim()) ?? 0,
      cLong: double.tryParse(_longControl.text.trim()) ?? 0,
      cNote: _noteControl.text.trim().isEmpty ? '-' : _noteControl.text.trim(),
    );
  }

  Widget _buildCountryDropdown({
    required String label,
    required String? value,
    required TextEditingController controller,
    required ValueChanged<String?> onChanged,
  }) {
    final countries = widget.countries;

    if (countries.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: const Text(
          'Keine Länder verfügbar – bitte country_tld.csv importieren',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      );
    }

    final sortedCountries = [...countries]
      ..sort((a, b) => a.coName.toLowerCase().compareTo(b.coName.toLowerCase()));

    return DropdownMenu<String>(
      controller: controller,
      initialSelection: value,
      width: 360,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: true,
      enableFilter: true,
      enableSearch: true,
      label: Text(label),
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
        return entries.where((entry) => entry.label.toLowerCase().startsWith(normalizedQuery)).toList();
      },
      dropdownMenuEntries: sortedCountries
          .map(
            (country) => DropdownMenuEntry<String>(
              value: country.coTld,
              label: country.coName,
            ),
          )
          .toList(),
      onSelected: (selectedValue) {
        controller.text = _countryNameForId(selectedValue);
        onChanged(selectedValue);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Kunde bearbeiten' : 'Neuer Kunde';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idControl,
              enabled: !_isEditing,
              decoration: const InputDecoration(labelText: 'ID (erforderlich)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _firstNameControl,
              decoration: const InputDecoration(labelText: 'Vorname (erforderlich)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameControl,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
              onChanged: (value) {
                final upper = value.toUpperCase();
                if (value != upper) {
                  _lastNameControl.value = _lastNameControl.value.copyWith(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length),
                  );
                }
              },
              decoration: const InputDecoration(labelText: 'Nachname (erforderlich)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _companyControl,
              decoration: const InputDecoration(labelText: 'Firma'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _dealer,
                      onChanged: (v) => setState(() => _dealer = v ?? false),
                    ),
                    const Text('Reseller'),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _vat,
                      onChanged: (v) => setState(() => _vat = v ?? false),
                    ),
                    const Text('keine MwSt'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vatIdControl,
              decoration: const InputDecoration(labelText: 'VAT-ID'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Rechnungsadresse',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _careofBControl,
              focusNode: _careofBFocusNode,
              decoration: const InputDecoration(labelText: '℅'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _streetBControl,
              focusNode: _streetBFocusNode,
              decoration: const InputDecoration(labelText: 'Straße (erforderlich)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _houseNumberBControl,
                    focusNode: _houseNumberBFocusNode,
                    decoration: const InputDecoration(labelText: 'Hausnr.'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _postalCodeBControl,
                    focusNode: _postalCodeBFocusNode,
                    decoration: const InputDecoration(labelText: 'PLZ (erforderlich)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityBControl,
              focusNode: _cityBFocusNode,
              decoration: const InputDecoration(labelText: 'Stadt (erforderlich)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stateBControl,
              focusNode: _stateBFocusNode,
              decoration: const InputDecoration(labelText: 'Verwaltungseinheit'),
            ),
            const SizedBox(height: 12),
            _buildCountryDropdown(
              label: 'Land (Rechnungsadresse, erforderlich)',
              value: _countryBId,
              controller: _countryBControl,
              onChanged: (v) async {
                setState(() {
                  _countryBId = v;
                  _countryDId = v;
                  _countryDControl.text = _countryNameForId(v);
                });
                await _updateStateFromCountryAndPostalCode(billing: true);
                await _updateStateFromCountryAndPostalCode(billing: false);
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Lieferadresse',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _careofDControl,
              decoration: const InputDecoration(labelText: '℅'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _streetDControl,
              decoration: const InputDecoration(labelText: 'Straße (erforderlich)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _houseNumberDControl,
                    decoration: const InputDecoration(labelText: 'Hausnr.'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _postalCodeDControl,
                    decoration: const InputDecoration(labelText: 'PLZ (erforderlich)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityDControl,
              decoration: const InputDecoration(labelText: 'Stadt (erforderlich)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stateDControl,
              decoration: const InputDecoration(labelText: 'Verwaltungseinheit'),
            ),
            const SizedBox(height: 12),
            _buildCountryDropdown(
              label: 'Land (Lieferadresse, erforderlich)',
              value: _countryDId,
              controller: _countryDControl,
              onChanged: (v) async {
                setState(() => _countryDId = v);
                await _updateStateFromCountryAndPostalCode(billing: false);
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _mailControl,
              decoration: const InputDecoration(labelText: 'E-Mail'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneControl,
              decoration: const InputDecoration(labelText: 'Telefon'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _webControl,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _socialMediaControl,
              decoration: const InputDecoration(labelText: 'Social Media'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Koordinaten',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latControl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Breitengrad (Lat)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _longControl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Längengrad (Long)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _noteControl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notiz',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (await _validateForm()) {
              if (!mounted) return;
              navigator.pop(_buildCustomer());
            }
          },
          child: Text(_isEditing ? 'Aktualisieren' : 'Erstellen'),
        ),
      ],
    );
  }
}
