import 'package:flutter/material.dart';

import '../../domain/customer.dart';

class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({
    super.key,
    this.customer,
  });

  final Customer? customer;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  late final TextEditingController _idControl;
  late final TextEditingController _lastNameControl;
  late final TextEditingController _firstNameControl;
  late final TextEditingController _companyControl;
  late final TextEditingController _streetBControl;
  late final TextEditingController _houseNumberBControl;
  late final TextEditingController _postalCodeBControl;
  late final TextEditingController _cityBControl;
  late final TextEditingController _countryBIdControl;
  late final TextEditingController _streetDControl;
  late final TextEditingController _houseNumberDControl;
  late final TextEditingController _postalCodeDControl;
  late final TextEditingController _cityDControl;
  late final TextEditingController _countryDIdControl;
  late final TextEditingController _mailControl;
  late final TextEditingController _phoneControl;

  late bool _dealer;
  late bool _vat;
  late bool _isEditing;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _isEditing = c != null;
    _idControl = TextEditingController(text: c?.cId ?? '');
    _lastNameControl = TextEditingController(text: c?.cLastName ?? '');
    _firstNameControl = TextEditingController(text: c?.cFirstName ?? '');
    _companyControl = TextEditingController(text: c?.cCompany ?? '-');
    _streetBControl = TextEditingController(text: c?.cStreetB ?? '');
    _houseNumberBControl = TextEditingController(text: c?.cHouseNumberB ?? '');
    _postalCodeBControl = TextEditingController(text: c?.cPostalCodeB ?? '');
    _cityBControl = TextEditingController(text: c?.cCityB ?? '');
    _countryBIdControl = TextEditingController(text: c?.cCountryBId ?? 'DE');
    _streetDControl = TextEditingController(text: c?.cStreetD ?? '');
    _houseNumberDControl = TextEditingController(text: c?.cHouseNumberD ?? '');
    _postalCodeDControl = TextEditingController(text: c?.cPostalCodeD ?? '');
    _cityDControl = TextEditingController(text: c?.cCityD ?? '');
    _countryDIdControl = TextEditingController(text: c?.cCountryDId ?? 'DE');
    _mailControl = TextEditingController(text: c?.cMail ?? '-');
    _phoneControl = TextEditingController(text: c?.cPhone ?? '-');
    _dealer = c?.cDealer ?? false;
    _vat = c?.cVat ?? false;
  }

  @override
  void dispose() {
    _idControl.dispose();
    _lastNameControl.dispose();
    _firstNameControl.dispose();
    _companyControl.dispose();
    _streetBControl.dispose();
    _houseNumberBControl.dispose();
    _postalCodeBControl.dispose();
    _cityBControl.dispose();
    _countryBIdControl.dispose();
    _streetDControl.dispose();
    _houseNumberDControl.dispose();
    _postalCodeDControl.dispose();
    _cityDControl.dispose();
    _countryDIdControl.dispose();
    _mailControl.dispose();
    _phoneControl.dispose();
    super.dispose();
  }

  bool _validateForm() {
    if (_idControl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID erforderlich')),
      );
      return false;
    }
    if (_lastNameControl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nachname erforderlich')),
      );
      return false;
    }
    if (_firstNameControl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vorname erforderlich')),
      );
      return false;
    }
    return true;
  }

  Customer _buildCustomer() {
    return Customer(
      cId: _idControl.text.trim(),
      cLastName: _lastNameControl.text.trim(),
      cFirstName: _firstNameControl.text.trim(),
      cCompany: _companyControl.text.trim().isEmpty ? '-' : _companyControl.text.trim(),
      cDealer: _dealer,
      cVat: _vat,
      cStreetB: _streetBControl.text.trim(),
      cHouseNumberB: _houseNumberBControl.text.trim(),
      cPostalCodeB: _postalCodeBControl.text.trim(),
      cCityB: _cityBControl.text.trim(),
      cCountryBId: _countryBIdControl.text.trim().isEmpty ? 'DE' : _countryBIdControl.text.trim(),
      cStreetD: _streetDControl.text.trim(),
      cHouseNumberD: _houseNumberDControl.text.trim(),
      cPostalCodeD: _postalCodeDControl.text.trim(),
      cCityD: _cityDControl.text.trim(),
      cCountryDId: _countryDIdControl.text.trim().isEmpty ? 'DE' : _countryDIdControl.text.trim(),
      cMail: _mailControl.text.trim().isEmpty ? '-' : _mailControl.text.trim(),
      cPhone: _phoneControl.text.trim().isEmpty ? '-' : _phoneControl.text.trim(),
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
                    const Text('MwSt.'),
                  ],
                ),
              ],
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
              controller: _streetBControl,
              decoration: const InputDecoration(labelText: 'Straße'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _houseNumberBControl,
                    decoration: const InputDecoration(labelText: 'Hausnr.'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _postalCodeBControl,
                    decoration: const InputDecoration(labelText: 'PLZ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityBControl,
              decoration: const InputDecoration(labelText: 'Stadt'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countryBIdControl,
              decoration: const InputDecoration(labelText: 'Land (Code)'),
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
              controller: _streetDControl,
              decoration: const InputDecoration(labelText: 'Straße'),
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
                    decoration: const InputDecoration(labelText: 'PLZ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityDControl,
              decoration: const InputDecoration(labelText: 'Stadt'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countryDIdControl,
              decoration: const InputDecoration(labelText: 'Land (Code)'),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (_validateForm()) {
              Navigator.pop(context, _buildCustomer());
            }
          },
          child: Text(_isEditing ? 'Aktualisieren' : 'Erstellen'),
        ),
      ],
    );
  }
}
