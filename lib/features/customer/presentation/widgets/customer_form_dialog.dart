import 'package:flutter/material.dart';

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
  late final TextEditingController _streetBControl;
  late final TextEditingController _houseNumberBControl;
  late final TextEditingController _postalCodeBControl;
  late final TextEditingController _cityBControl;
  late final TextEditingController _streetDControl;
  late final TextEditingController _houseNumberDControl;
  late final TextEditingController _postalCodeDControl;
  late final TextEditingController _cityDControl;
  late final TextEditingController _mailControl;
  late final TextEditingController _phoneControl;

  String? _countryBId;
  String? _countryDId;
  // Autocomplete-Controller für Suchfeld
  late TextEditingController _countryBTextControl;
  late TextEditingController _countryDTextControl;
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
    _countryBId = c?.cCountryBId?.toLowerCase();
    _countryBTextControl = TextEditingController(
      text: _countryDisplayText(_countryBId),
    );
    _streetDControl = TextEditingController(text: c?.cStreetD ?? '');
    _houseNumberDControl = TextEditingController(text: c?.cHouseNumberD ?? '');
    _postalCodeDControl = TextEditingController(text: c?.cPostalCodeD ?? '');
    _cityDControl = TextEditingController(text: c?.cCityD ?? '');
    _countryDId = c?.cCountryDId?.toLowerCase();
    _countryDTextControl = TextEditingController(
      text: _countryDisplayText(_countryDId),
    );
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
    _streetDControl.dispose();
    _houseNumberDControl.dispose();
    _postalCodeDControl.dispose();
    _cityDControl.dispose();
    _countryBTextControl.dispose();
    _countryDTextControl.dispose();
    _mailControl.dispose();
    _phoneControl.dispose();
    super.dispose();
  }

  bool _validateId(String cId) {
    if (cId.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cId)) {
      return false;
    }
    final year = int.parse(cId.substring(0, 2));
    final month = int.parse(cId.substring(2, 4));
    final day = int.parse(cId.substring(4, 6));
    final hour = int.parse(cId.substring(6, 8));
    final minute = int.parse(cId.substring(8, 10));
    final currentYear = DateTime.now().year % 100;

    if (year > currentYear) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    if (hour > 23) return false;
    if (minute > 59) return false;

    // Prüfe ob das Datum tatsächlich existiert
    final date = DateTime(2000 + year, month, day);
    if (date.month != month || date.day != day) return false;

    return true;
  }

  bool _validateForm() {
    final cId = _idControl.text.trim();
    if (cId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID erforderlich')),
      );
      return false;
    }
    if (!_validateId(cId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ungültige ID – Format: JJMMTTHHMM (10 Ziffern, gültiges Datum/Uhrzeit, nicht in der Zukunft)',
          ),
        ),
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
      cCountryBId: _countryBId,
      cStreetD: _streetDControl.text.trim(),
      cHouseNumberD: _houseNumberDControl.text.trim(),
      cPostalCodeD: _postalCodeDControl.text.trim(),
      cCityD: _cityDControl.text.trim(),
      cCountryDId: _countryDId,
      cMail: _mailControl.text.trim().isEmpty ? '-' : _mailControl.text.trim(),
      cPhone: _phoneControl.text.trim().isEmpty ? '-' : _phoneControl.text.trim(),
    );
  }

  String _countryDisplayText(String? tld) {
    if (tld == null) return '';
    final match = widget.countries.where((c) => c.coTld == tld).firstOrNull;
    if (match == null) return tld.toUpperCase();
    return '${match.coTld.toUpperCase()} – ${match.coName}';
  }

  Widget _buildCountryDropdown({
    required String label,
    required String? value,
    required TextEditingController textController,
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

    return Autocomplete<CountryTld>(
      initialValue: TextEditingValue(text: _countryDisplayText(value)),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        // Externen Controller synchron halten
        controller.addListener(() {
          if (textController.text != controller.text) {
            textController.text = controller.text;
          }
        });
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Auswahl aufheben',
                    onPressed: () {
                      controller.clear();
                      onChanged(null);
                    },
                  )
                : null,
          ),
        );
      },
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.toLowerCase().trim();
        if (query.isEmpty) return countries;
        return countries.where(
          (c) =>
              c.coTld.toLowerCase().contains(query) ||
              c.coName.toLowerCase().contains(query),
        );
      },
      displayStringForOption: (c) => '${c.coTld.toUpperCase()} – ${c.coName}',
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final c = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text('${c.coTld.toUpperCase()} – ${c.coName}'),
                    onTap: () => onSelected(c),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (c) => onChanged(c.coTld),
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
            _buildCountryDropdown(
              label: 'Land (Rechnungsadresse)',
              value: _countryBId,
              textController: _countryBTextControl,
              onChanged: (v) => setState(() => _countryBId = v),
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
            _buildCountryDropdown(
              label: 'Land (Lieferadresse)',
              value: _countryDId,
              textController: _countryDTextControl,
              onChanged: (v) => setState(() => _countryDId = v),
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
