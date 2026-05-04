import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  late final FocusNode _careofDFocusNode;
  late final FocusNode _streetBFocusNode;
  late final FocusNode _houseNumberBFocusNode;
  late final FocusNode _postalCodeBFocusNode;
  late final FocusNode _postalCodeDFocusNode;
  late final FocusNode _cityBFocusNode;
  late final FocusNode _stateBFocusNode;
  late final FocusNode _stateDFocusNode;
  late final FocusNode _companyFocusNode;
  late final FocusNode _vatIdFocusNode;
  late final FocusNode _mailFocusNode;
  late final FocusNode _phoneFocusNode;
  late final FocusNode _webFocusNode;
  late final FocusNode _socialMediaFocusNode;
  late final FocusNode _noteFocusNode;
  late final FocusNode _countryBFocusNode;
  late final FocusNode _countryDFocusNode;

  String? _countryBId;
  String? _countryDId;
  String? _countryBIdOnFocus;
  String? _countryDIdOnFocus;
  late bool _dealer;
  late bool _vat;
  late bool _isEditing;
  bool _isFetchingCoordinates = false;


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

  void _handleDashPlaceholderOnFocusChange({
    required FocusNode focusNode,
    required TextEditingController controller,
    TextEditingController? mirrorOnBlur,
  }) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        if (controller.text.trim() == '-') {
          controller.clear();
        }
        return;
      }

      final trimmed = controller.text.trim();
      final normalized = trimmed.isEmpty ? '-' : trimmed;
      if (controller.text != normalized) {
        controller.value = controller.value.copyWith(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
          composing: TextRange.empty,
        );
      }
      if (mirrorOnBlur != null) {
        mirrorOnBlur.text = normalized;
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
    _careofDFocusNode = FocusNode();
    _stateDFocusNode = FocusNode();
    _companyFocusNode = FocusNode();
    _vatIdFocusNode = FocusNode();
    _mailFocusNode = FocusNode();
    _phoneFocusNode = FocusNode();
    _webFocusNode = FocusNode();
    _socialMediaFocusNode = FocusNode();
    _noteFocusNode = FocusNode();
    _countryBFocusNode = FocusNode();
    _countryDFocusNode = FocusNode();

    _handleDashPlaceholderOnFocusChange(
      focusNode: _careofBFocusNode,
      controller: _careofBControl,
      mirrorOnBlur: _careofDControl,
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
    _postalCodeBFocusNode.addListener(() {
      if (!_postalCodeBFocusNode.hasFocus) {
        _updateStateFromCountryAndPostalCode(billing: true);
        _updateStateFromCountryAndPostalCode(billing: false);
      }
    });
    _postalCodeDFocusNode = FocusNode();
    _postalCodeDFocusNode.addListener(() {
      if (!_postalCodeDFocusNode.hasFocus) {
        _updateStateFromCountryAndPostalCode(billing: false);
      }
    });
    _countryBFocusNode.addListener(() {
      if (_countryBFocusNode.hasFocus) {
        _countryBIdOnFocus = _countryBId;
        return;
      }

      _countryBControl.text = _countryNameForId(_countryBId);
      if (_countryBId != _countryBIdOnFocus) {
        _updateStateFromCountryAndPostalCode(billing: true);
        _updateStateFromCountryAndPostalCode(billing: false);
      }
    });
    _countryDFocusNode.addListener(() {
      if (_countryDFocusNode.hasFocus) {
        _countryDIdOnFocus = _countryDId;
        return;
      }

      _countryDControl.text = _countryNameForId(_countryDId);
      if (_countryDId != _countryDIdOnFocus) {
        _updateStateFromCountryAndPostalCode(billing: false);
      }
    });
    _syncOnBlur(
      focusNode: _cityBFocusNode,
      source: _cityBControl,
      target: _cityDControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _stateBFocusNode,
      controller: _stateBControl,
      mirrorOnBlur: _stateDControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _careofDFocusNode,
      controller: _careofDControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _stateDFocusNode,
      controller: _stateDControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _companyFocusNode,
      controller: _companyControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _vatIdFocusNode,
      controller: _vatIdControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _mailFocusNode,
      controller: _mailControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _phoneFocusNode,
      controller: _phoneControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _webFocusNode,
      controller: _webControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _socialMediaFocusNode,
      controller: _socialMediaControl,
    );
    _handleDashPlaceholderOnFocusChange(
      focusNode: _noteFocusNode,
      controller: _noteControl,
    );

    final lat = double.tryParse(_latControl.text) ?? 0;
    final lng = double.tryParse(_longControl.text) ?? 0;
    if (lat == 0 && lng == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCoordinates());
    }
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
    _careofDFocusNode.dispose();
    _streetBFocusNode.dispose();
    _houseNumberBFocusNode.dispose();
    _postalCodeBFocusNode.dispose();
    _postalCodeDFocusNode.dispose();
    _cityBFocusNode.dispose();
    _stateBFocusNode.dispose();
    _stateDFocusNode.dispose();
    _companyFocusNode.dispose();
    _vatIdFocusNode.dispose();
    _mailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _webFocusNode.dispose();
    _socialMediaFocusNode.dispose();
    _noteFocusNode.dispose();
    _countryBFocusNode.dispose();
    _countryDFocusNode.dispose();
    super.dispose();
  }

  String? _validateId(String cId) {
    if (cId.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cId)) {
      return 'Die Kundennummer muss genau 10 Ziffern haben.';
    }

    final year = int.parse(cId.substring(0, 2));
    final month = int.parse(cId.substring(2, 4));
    final day = int.parse(cId.substring(4, 6));
    final hour = int.parse(cId.substring(6, 8));
    final minute = int.parse(cId.substring(8, 10));
    final currentYear = DateTime.now().year % 100;

    if (year < 0 || year > currentYear) {
      return 'Die ersten 2 Ziffern der Kundennummer müssen zwischen 00 und $currentYear liegen.';
    }
    if (month < 1 || month > 12) {
      return 'Die 3. und 4. Ziffer der Kundennummer müssen zwischen 01 und 12 liegen.';
    }
    if (day < 1 || day > 31) {
      return 'Die 5. und 6. Ziffer der Kundennummer müssen zwischen 01 und 31 liegen.';
    }
    if (hour < 0 || hour > 23) {
      return 'Die 7. und 8. Ziffer der Kundennummer müssen zwischen 00 und 23 liegen.';
    }
    if (minute < 0 || minute > 59) {
      return 'Die 9. und 10. Ziffer der Kundennummer müssen zwischen 00 und 59 liegen.';
    }

    final date = DateTime(2000 + year, month, day);
    if (date.month != month || date.day != day) {
      return 'Die Kundennummer ist ungültig.';
    }

    return null;
  }

  bool _isGermany(String? countryId) {
    return countryId?.trim().toLowerCase() == 'de';
  }

  bool _isUSA(String? countryId) {
    return countryId?.trim().toLowerCase() == 'us';
  }

  Future<String?> _resolveUSState(String postalCode) async {
    // US ZIP+4-Format (z.B. "94040-1234") → nur die 5-stellige Basis-ZIP verwenden
    final zip = postalCode.trim().split('-').first.trim();
    if (zip.isEmpty) {
      return null;
    }

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'postalcode': zip,
        'country': 'us',
        'format': 'json',
        'addressdetails': '1',
        'limit': '1',
      },
    );

    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {'User-Agent': 'arrow_ops/1.0'},
      );
    } catch (_) {
      return null;
    }

    if (response.statusCode != 200) {
      return null;
    }

    List<dynamic> results;
    try {
      results = jsonDecode(response.body) as List<dynamic>;
    } catch (_) {
      return null;
    }

    if (results.isEmpty) return null;

    final firstResult = results[0];
    if (firstResult is! Map<String, dynamic>) return null;

    final addressRaw = firstResult['address'];
    if (addressRaw == null) return null;

    final address = Map<String, dynamic>.from(addressRaw as Map);

    final stateFull = address['state']?.toString().trim() ?? '';
    // ISO3166-2-lvl4 liefert z.B. 'US-CA'
    final isoCode = address['ISO3166-2-lvl4']?.toString().trim() ?? '';
    final stateShort = isoCode.contains('-')
        ? isoCode.split('-').last.trim()
        : isoCode;

    if (stateFull.isEmpty && stateShort.isEmpty) {
      return null;
    }
    if (stateShort.isEmpty) {
      return stateFull;
    }
    if (stateFull.isEmpty) {
      return stateShort;
    }
    return '$stateShort - $stateFull';
  }

  /// Wandelt Länder-TLDs in ISO-3166-Alpha-2-Codes um (für Nominatim countrycodes).
  String _tldToIso(String tld) {
    const mapping = <String, String>{
      'uk': 'gb', // .uk TLD → GB (United Kingdom)
      'ac': 'sh', // Ascension Island → Saint Helena (ISO)
      'eu': '',   // EU-TLD → kein Ländercode
    };
    return mapping[tld] ?? tld;
  }

  Future<void> _fetchCoordinates() async {
    final rawCode = _countryDId?.trim().toLowerCase() ?? '';
    final countryCode = _tldToIso(rawCode);
    final countryName = _countryNameForId(_countryDId);

    final street = _streetDControl.text.trim();
    final houseNumber = _houseNumberDControl.text.trim();
    final postalCode = _postalCodeDControl.text.trim();
    final city = _cityDControl.text.trim();

    // Straßenname + Hausnummer kombinieren (Hausnummer voran, internationaler Standard)
    final streetWithNumber = [
      if (houseNumber.isNotEmpty && houseNumber != '-') houseNumber,
      if (street.isNotEmpty) street,
    ].join(' ');

    final messenger = ScaffoldMessenger.of(context);

    if (streetWithNumber.trim().isEmpty && postalCode.isEmpty && city.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Lieferadresse ist unvollständig.')),
      );
      return;
    }

    setState(() => _isFetchingCoordinates = true);

    try {
      // 1. Versuch: strukturierte Nominatim-API (präziser bei Hausnummern)
      final structuredParams = <String, String>{
        'format': 'json',
        'limit': '1',
        'addressdetails': '0',
      };
      if (streetWithNumber.isNotEmpty) structuredParams['street'] = streetWithNumber;
      if (postalCode.isNotEmpty) structuredParams['postalcode'] = postalCode;
      if (city.isNotEmpty) structuredParams['city'] = city;
      if (countryCode.isNotEmpty) {
        structuredParams['countrycodes'] = countryCode;
      } else if (countryName.isNotEmpty) {
        structuredParams['country'] = countryName;
      }

      var results = await _nominatimSearch(structuredParams);

      // 2. Fallback: freie Suche (besser bei unvollständigen Adressen)
      if (results.isEmpty) {
        final freeParts = [
          streetWithNumber,
          if (postalCode.isNotEmpty) postalCode,
          if (city.isNotEmpty) city,
          if (countryCode.isEmpty && countryName.isNotEmpty) countryName,
        ].where((s) => s.isNotEmpty).toList();

        final freeParams = <String, String>{
          'q': freeParts.join(', '),
          'format': 'json',
          'limit': '1',
        };
        if (countryCode.isNotEmpty) freeParams['countrycodes'] = countryCode;

        results = await _nominatimSearch(freeParams);
      }

      if (!mounted) return;

      if (results.isEmpty) {
        final displayAddr = [streetWithNumber, postalCode, city, if (countryCode.isEmpty) countryName]
            .where((s) => s.isNotEmpty)
            .join(', ');
        messenger.showSnackBar(
          SnackBar(
            content: Text('Keine Koordinaten gefunden für:\n$displayAddr'),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      final first = results[0] as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lon == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Koordinaten konnten nicht aus lat/lon gelesen werden.')),
        );
        return;
      }

      setState(() {
        _latControl.text = lat.toString();
        _longControl.text = lon.toString();
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _isFetchingCoordinates = false);
    }
  }

  Future<List<dynamic>> _nominatimSearch(Map<String, String> params) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final response = await http.get(uri, headers: {'User-Agent': 'arrow_ops/1.0'});
      if (response.statusCode != 200) return [];
      final results = jsonDecode(response.body);
      if (results is List) return results;
      return [];
    } catch (_) {
      return [];
    }
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
    final postalCode = billing ? _postalCodeBControl.text : _postalCodeDControl.text;

    String? resolvedState;
    if (_isGermany(countryId)) {
      resolvedState = await _resolveGermanState(postalCode);
    } else if (_isUSA(countryId)) {
      resolvedState = await _resolveUSState(postalCode);
    }

    if (!mounted || resolvedState == null || resolvedState.isEmpty) {
      return;
    }

    setState(() {
      if (billing) {
        _stateBControl.text = resolvedState!;
      } else {
        _stateDControl.text = resolvedState!;
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
        const SnackBar(content: Text('Vorname darf nur Buchstaben und Leerzeichen enthalten.')),

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
        const SnackBar(content: Text('Nachname darf nur Buchstaben und Leerzeichen enthalten.')),

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
        const SnackBar(content: Text('Straßenname ist zu kurz.')),

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
          const SnackBar(content: Text('Stadt (Rechnungsadresse) muss mindestens 2 Buchstaben enthalten und darf nur alphabetische Zeichen enthalten.')),

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
          const SnackBar(content: Text('Bitte eine gültige PLZ für die Rechnungsadresse eingeben.')),

        );
        return false;
      }
      _stateBControl.text = billingState;
    } else if (_isUSA(_countryBId)) {
      final billingState = await _resolveUSState(_postalCodeBControl.text);
      if (!mounted) {
        return false;
      }
      if (billingState != null && billingState.isNotEmpty) {
        _stateBControl.text = billingState;
      }
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
          const SnackBar(content: Text('Stadt (Lieferadresse) muss mindestens 2 Buchstaben enthalten und darf nur alphabetische Zeichen enthalten.')),

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
          const SnackBar(content: Text('Bitte eine gültige PLZ für die Lieferadresse eingeben.')),

        );
        return false;
      }
      _stateDControl.text = deliveryState;
    } else if (_isUSA(_countryDId)) {
      final deliveryState = await _resolveUSState(_postalCodeDControl.text);
      if (!mounted) {
        return false;
      }
      if (deliveryState != null && deliveryState.isNotEmpty) {
        _stateDControl.text = deliveryState;
      }
    }
    final mail = _mailControl.text.trim();
    if (mail.isNotEmpty && mail != '-') {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Bitte eine gültige E-Mail-Adresse eingeben.')),
        );
        return false;
      }
    }
    return true;
  }

  Customer _buildCustomer() {
    final lastName = _lastNameControl.text.trim().toUpperCase();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

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
      cLastModified: now,
    );
  }

  Widget _buildCountryDropdown({
    required String label,
    required String? value,
    required TextEditingController controller,
    required FocusNode focusNode,
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
      focusNode: focusNode,
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

  Widget _buildAddressFields({required bool billing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          billing ? 'Rechnungsadresse' : 'Lieferadresse',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: billing ? _careofBControl : _careofDControl,
          focusNode: billing ? _careofBFocusNode : _careofDFocusNode,
          decoration: const InputDecoration(labelText: '℅'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: billing ? _streetBControl : _streetDControl,
          focusNode: billing ? _streetBFocusNode : null,
          decoration: const InputDecoration(labelText: 'Straße (erforderlich)'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: billing ? _houseNumberBControl : _houseNumberDControl,
                focusNode: billing ? _houseNumberBFocusNode : null,
                decoration: const InputDecoration(labelText: 'Hausnr.'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextField(
                controller: billing ? _postalCodeBControl : _postalCodeDControl,
                focusNode: billing ? _postalCodeBFocusNode : _postalCodeDFocusNode,
                decoration: const InputDecoration(labelText: 'PLZ (erforderlich)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: billing ? _cityBControl : _cityDControl,
          focusNode: billing ? _cityBFocusNode : null,
          decoration: const InputDecoration(labelText: 'Stadt (erforderlich)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: billing ? _stateBControl : _stateDControl,
          focusNode: billing ? _stateBFocusNode : _stateDFocusNode,
          decoration: const InputDecoration(labelText: 'Verwaltungseinheit'),
        ),
        const SizedBox(height: 12),
        _buildCountryDropdown(
          label: billing
              ? 'Land (Rechnungsadresse, erforderlich)'
              : 'Land (Lieferadresse, erforderlich)',
          value: billing ? _countryBId : _countryDId,
          controller: billing ? _countryBControl : _countryDControl,
          focusNode: billing ? _countryBFocusNode : _countryDFocusNode,
          onChanged: billing
              ? (v) {
                  setState(() {
                    _countryBId = v;
                    _countryDId = v;
                    _countryDControl.text = _countryNameForId(v);
                  });
                }
              : (v) {
                  setState(() => _countryDId = v);
                },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 700;
    final title = _isEditing ? 'Kunde bearbeiten' : 'Neuer Kunde';

    final addressSection = isWide
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildAddressFields(billing: true)),
                const SizedBox(width: 16),
                const VerticalDivider(),
                const SizedBox(width: 16),
                Expanded(child: _buildAddressFields(billing: false)),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAddressFields(billing: true),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _buildAddressFields(billing: false),
            ],
          );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 12,
        vertical: 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 900 : 500,
          maxHeight: screenSize.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      focusNode: _companyFocusNode,
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
                      focusNode: _vatIdFocusNode,
                      decoration: const InputDecoration(labelText: 'VAT-ID'),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    addressSection,
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _mailControl,
                      focusNode: _mailFocusNode,
                      decoration: const InputDecoration(labelText: 'E-Mail'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneControl,
                      focusNode: _phoneFocusNode,
                      decoration: const InputDecoration(labelText: 'Telefon'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webControl,
                      focusNode: _webFocusNode,
                      decoration: const InputDecoration(labelText: 'Website'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _socialMediaControl,
                      focusNode: _socialMediaFocusNode,
                      decoration: const InputDecoration(labelText: 'Social Media'),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Koordinaten',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isFetchingCoordinates ? null : _fetchCoordinates,
                      icon: _isFetchingCoordinates
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.location_on_outlined),
                      label: const Text('Koordinaten aus Lieferadresse ermitteln'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _latControl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Breitengrad (Lat)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _longControl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
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
                      focusNode: _noteFocusNode,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notiz',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isEditing &&
                        widget.customer?.cLastModified != null &&
                        widget.customer!.cLastModified > 0)
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Zuletzt geändert'),
                        child: Text(
                          () {
                            final dt = DateTime.fromMillisecondsSinceEpoch(
                                widget.customer!.cLastModified * 1000);
                            return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                          }(),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
