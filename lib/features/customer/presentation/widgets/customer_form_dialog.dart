import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/database/app_database.dart';
import '../../../../core/ui/transient_feedback.dart';
import '../../data/italian_billing_province_resolver.dart';
import '../../domain/country_tld.dart';
import '../../domain/customer.dart';

enum _DialogSnackBarType { validation, info, warning, error }

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
  void _showDialogSnackBar(
    String message, {
    _DialogSnackBarType type = _DialogSnackBarType.info,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final duration = switch (type) {
      _DialogSnackBarType.validation => const Duration(seconds: 2),
      _DialogSnackBarType.info => const Duration(seconds: 3),
      _DialogSnackBarType.warning => const Duration(seconds: 4),
      _DialogSnackBarType.error => const Duration(seconds: 5),
    };

    final iconData = switch (type) {
      _DialogSnackBarType.validation => Icons.rule_folder_outlined,
      _DialogSnackBarType.info => Icons.info_outline,
      _DialogSnackBarType.warning => Icons.warning_amber_rounded,
      _DialogSnackBarType.error => Icons.error_outline,
    };

    final backgroundColor = switch (type) {
      _DialogSnackBarType.validation => colorScheme.secondaryContainer,
      _DialogSnackBarType.info => colorScheme.primaryContainer,
      _DialogSnackBarType.warning => Colors.amber.shade200,
      _DialogSnackBarType.error => colorScheme.errorContainer,
    };

    final foregroundColor = switch (type) {
      _DialogSnackBarType.validation => colorScheme.onSecondaryContainer,
      _DialogSnackBarType.info => colorScheme.onPrimaryContainer,
      _DialogSnackBarType.warning => Colors.brown.shade900,
      _DialogSnackBarType.error => colorScheme.onErrorContainer,
    };

    TransientFeedback.show(
      context,
      message: message,
      duration: duration,
      iconData: iconData,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }

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
    _longControl = TextEditingController(text: c != null ? c.cLon.toString() : '0');
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
        _updateStateFromCountryAndPostalCode(
          billing: true,
          clearWhenUnresolved: true,
        );
        _updateStateFromCountryAndPostalCode(
          billing: false,
          clearWhenUnresolved: true,
        );
      }
    });
    _countryDFocusNode.addListener(() {
      if (_countryDFocusNode.hasFocus) {
        _countryDIdOnFocus = _countryDId;
        return;
      }

      _countryDControl.text = _countryNameForId(_countryDId);
      if (_countryDId != _countryDIdOnFocus) {
        _updateStateFromCountryAndPostalCode(
          billing: false,
          clearWhenUnresolved: true,
        );
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

    // Ensure Italian administrative units are visible immediately in the form.
    _resolveItalianStateInControllers(billing: true);
    _resolveItalianStateInControllers(billing: false);
    _resolveUSStateInControllers(billing: true);
    _resolveUSStateInControllers(billing: false);
    _resolveAustraliaStateInControllers(billing: true);
    _resolveAustraliaStateInControllers(billing: false);
    _resolveSwissStateInControllers(billing: true);
    _resolveSwissStateInControllers(billing: false);
    if (_isItaly(_countryBId) || _isUSA(_countryBId) || _isAustralia(_countryBId) || _isSwitzerland(_countryBId)) {
      _updateStateFromCountryAndPostalCode(billing: true);
    }
    if (_isItaly(_countryDId) || _isUSA(_countryDId) || _isAustralia(_countryDId) || _isSwitzerland(_countryDId)) {
      _updateStateFromCountryAndPostalCode(billing: false);
    }

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
    return isUsCountry(countryId);
  }

  bool _isItaly(String? countryId) {
    return isItalyCountry(countryId);
  }

  bool _isAustralia(String? countryId) {
    return isAustraliaCountry(countryId);
  }

  bool _isSwitzerland(String? countryId) {
    return isSwitzerlandCountry(countryId);
  }

  void _resolveItalianStateInControllers({required bool billing}) {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isItaly(countryId)) {
      return;
    }

    final cityText = billing ? _cityBControl.text : _cityDControl.text;
    final cityControl = billing ? _cityBControl : _cityDControl;
    final stateControl = billing ? _stateBControl : _stateDControl;
    stateControl.text = resolveItalianBillingProvince(
      countryCode: countryId,
      currentState: stateControl.text,
      city: cityText,
    );
    cityControl.text = appendItalianProvinceAbbreviationToCity(
      city: cityControl.text,
      administrativeUnit: stateControl.text,
    );
  }

  void _resolveUSStateInControllers({required bool billing}) {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isUSA(countryId)) {
      return;
    }

    final cityControl = billing ? _cityBControl : _cityDControl;
    final stateControl = billing ? _stateBControl : _stateDControl;
    stateControl.text = resolveUSStateAdministrativeUnit(
      countryCode: countryId,
      currentState: stateControl.text,
      city: cityControl.text,
    );
    cityControl.text = appendUSStateAbbreviationToCity(
      city: cityControl.text,
      administrativeUnit: stateControl.text,
    );
  }

  void _resolveAustraliaStateInControllers({required bool billing}) {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isAustralia(countryId)) {
      return;
    }

    final cityControl = billing ? _cityBControl : _cityDControl;
    final stateControl = billing ? _stateBControl : _stateDControl;
    stateControl.text = resolveAustralianStateAdministrativeUnit(
      countryCode: countryId,
      currentState: stateControl.text,
      city: cityControl.text,
    );
  }

  void _resolveSwissStateInControllers({required bool billing}) {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isSwitzerland(countryId)) {
      return;
    }

    final cityControl = billing ? _cityBControl : _cityDControl;
    final stateControl = billing ? _stateBControl : _stateDControl;
    stateControl.text = resolveSwissCantonAdministrativeUnit(
      countryCode: countryId,
      currentState: stateControl.text,
      city: cityControl.text,
    );
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
    final mergedState =
        stateShort.isEmpty
            ? stateFull
            : (stateFull.isEmpty ? stateShort : '$stateShort - $stateFull');
    final canonical = resolveUSStateAdministrativeUnit(
      countryCode: 'us',
      currentState: mergedState,
      city: '',
    );
    return canonical == '-' ? null : canonical;
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

  bool _isIsoAlpha2CountryCode(String value) {
    return RegExp(r'^[a-z]{2}$').hasMatch(value);
  }

  Future<void> _fetchCoordinates() async {
    final rawCode = _countryDId?.trim().toLowerCase() ?? '';
    final resolvedCountryCode = _tldToIso(rawCode).trim().toLowerCase();
    final countryCode =
        _isIsoAlpha2CountryCode(resolvedCountryCode) ? resolvedCountryCode : '';
    final countryName = _countryNameForId(_countryDId);

    final street = _streetDControl.text.trim();
    final houseNumber = _houseNumberDControl.text.trim();
    final postalCode = _postalCodeDControl.text.trim();
    final city = _cityDControl.text.trim();

    final streetWithNumberHouseFirst = [
      if (houseNumber.isNotEmpty && houseNumber != '-') houseNumber,
      if (street.isNotEmpty) street,
    ].join(' ');
    final streetWithNumberStreetFirst = [
      if (street.isNotEmpty) street,
      if (houseNumber.isNotEmpty && houseNumber != '-') houseNumber,
    ].join(' ');

    if (streetWithNumberHouseFirst.trim().isEmpty && postalCode.isEmpty && city.isEmpty) {
      _showDialogSnackBar('Lieferadresse ist unvollständig.', type: _DialogSnackBarType.validation);
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
      if (streetWithNumberHouseFirst.isNotEmpty) {
        structuredParams['street'] = streetWithNumberHouseFirst;
      }
      if (postalCode.isNotEmpty) structuredParams['postalcode'] = postalCode;
      if (city.isNotEmpty) structuredParams['city'] = city;
      if (countryCode.isNotEmpty) {
        structuredParams['countrycodes'] = countryCode;
      } else if (countryName.isNotEmpty) {
        structuredParams['country'] = countryName;
      }

      var results = await _nominatimSearch(structuredParams);

      if (results.isEmpty &&
          streetWithNumberStreetFirst.isNotEmpty &&
          streetWithNumberStreetFirst != streetWithNumberHouseFirst) {
        final structuredStreetFirst = Map<String, String>.from(
          structuredParams,
        )..['street'] = streetWithNumberStreetFirst;
        results = await _nominatimSearch(structuredStreetFirst);
      }

      // Bei Tippfehlern im Ortsnamen hilft oft ein Retry ohne Stadtfeld.
      if (results.isEmpty && city.isNotEmpty) {
        final structuredParamsWithoutCity = Map<String, String>.from(
          structuredParams,
        )..remove('city');
        results = await _nominatimSearch(structuredParamsWithoutCity);

        if (results.isEmpty &&
            streetWithNumberStreetFirst.isNotEmpty &&
            streetWithNumberStreetFirst != streetWithNumberHouseFirst) {
          final structuredStreetFirstWithoutCity = Map<String, String>.from(
            structuredParamsWithoutCity,
          )..['street'] = streetWithNumberStreetFirst;
          results = await _nominatimSearch(structuredStreetFirstWithoutCity);
        }
      }

      // 2. Fallback: freie Suche (besser bei unvollständigen Adressen)
      if (results.isEmpty) {
        final freeStreetCandidates = <String>[
          streetWithNumberHouseFirst,
          if (streetWithNumberStreetFirst.isNotEmpty &&
              streetWithNumberStreetFirst != streetWithNumberHouseFirst)
            streetWithNumberStreetFirst,
        ];

        for (final freeStreet in freeStreetCandidates) {
          final freeParts = [
            freeStreet,
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
          if (results.isNotEmpty) {
            break;
          }
        }

        if (results.isEmpty && city.isNotEmpty) {
          final freeStreetCandidatesWithoutCity = <String>[
            streetWithNumberHouseFirst,
            if (streetWithNumberStreetFirst.isNotEmpty &&
                streetWithNumberStreetFirst != streetWithNumberHouseFirst)
              streetWithNumberStreetFirst,
          ];

          for (final freeStreet in freeStreetCandidatesWithoutCity) {
            final freePartsWithoutCity = [
              freeStreet,
              if (postalCode.isNotEmpty) postalCode,
              if (countryCode.isEmpty && countryName.isNotEmpty) countryName,
            ].where((s) => s.isNotEmpty).toList();

            if (freePartsWithoutCity.isNotEmpty) {
              final freeParamsWithoutCity = <String, String>{
                'q': freePartsWithoutCity.join(', '),
                'format': 'json',
                'limit': '1',
              };
              if (countryCode.isNotEmpty) {
                freeParamsWithoutCity['countrycodes'] = countryCode;
              }
              results = await _nominatimSearch(freeParamsWithoutCity);
              if (results.isNotEmpty) {
                break;
              }
            }
          }
        }
      }

      if (!mounted) return;

      if (results.isEmpty) {
        final displayAddr = [
          streetWithNumberStreetFirst.isEmpty
              ? streetWithNumberHouseFirst
              : streetWithNumberStreetFirst,
          postalCode,
          city,
          if (countryCode.isEmpty) countryName,
        ]
            .where((s) => s.isNotEmpty)
            .join(', ');
        _showDialogSnackBar(
          'Keine Koordinaten gefunden für:\n$displayAddr',
          type: _DialogSnackBarType.warning,
        );
        return;
      }

      final first = results[0] as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lon == null) {
        _showDialogSnackBar(
          'Koordinaten konnten nicht aus lat/lon gelesen werden.',
          type: _DialogSnackBarType.error,
        );
        return;
      }

      setState(() {
        _latControl.text = lat.toString();
        _longControl.text = lon.toString();
      });
    } catch (e) {
      if (!mounted) return;
      _showDialogSnackBar('Fehler: $e', type: _DialogSnackBarType.error);
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

  Future<void> _updateStateFromCountryAndPostalCode({
    required bool billing,
    bool clearWhenUnresolved = false,
  }) async {
    final countryId = billing ? _countryBId : _countryDId;
    final postalCode = billing ? _postalCodeBControl.text : _postalCodeDControl.text;
    final city = billing ? _cityBControl.text : _cityDControl.text;
    final currentState = billing ? _stateBControl.text : _stateDControl.text;

    String? resolvedState;
    if (_isGermany(countryId)) {
      resolvedState = await _resolveGermanState(postalCode);
    } else if (_isUSA(countryId)) {
      resolvedState = await _resolveUSState(postalCode);
    } else if (_isAustralia(countryId)) {
      resolvedState = resolveAustralianStateAdministrativeUnit(
        countryCode: countryId,
        currentState: currentState,
        city: city,
      );
      final isUnresolvedAustralianState =
          resolvedState.trim().isEmpty || resolvedState.trim() == '-';
      if (isUnresolvedAustralianState) {
        final resolvedByLookup = await _resolveAustralianStateFromNominatim(
          postalCode: postalCode,
          city: city,
        );
        if (resolvedByLookup != null && resolvedByLookup.isNotEmpty) {
          resolvedState = resolvedByLookup;
        }
      }
    } else if (_isSwitzerland(countryId)) {
      resolvedState = resolveSwissCantonAdministrativeUnit(
        countryCode: countryId,
        currentState: currentState,
        city: city,
      );
      final isUnresolvedSwissState =
          resolvedState.trim().isEmpty || resolvedState.trim() == '-';
      if (isUnresolvedSwissState) {
        final resolvedByLookup = await _resolveSwissStateFromNominatim(
          postalCode: postalCode,
          city: city,
        );
        if (resolvedByLookup != null && resolvedByLookup.isNotEmpty) {
          resolvedState = resolvedByLookup;
        }
      }
    } else if (_isItaly(countryId)) {
      resolvedState = resolveItalianBillingProvince(
        countryCode: countryId,
        currentState: currentState,
        city: city,
      );
      final isUnresolvedItalyState = resolvedState.trim().isEmpty || resolvedState.trim() == '-';
      if (isUnresolvedItalyState) {
        final resolvedByLookup = await _resolveItalianStateFromNominatim(
          postalCode: postalCode,
          city: city,
        );
        if (resolvedByLookup != null && resolvedByLookup.isNotEmpty) {
          resolvedState = resolvedByLookup;
        }
      }
    }

    if (!mounted) {
      return;
    }

    final normalizedResolvedState = resolvedState?.trim() ?? '';
    if (normalizedResolvedState.isEmpty || normalizedResolvedState == '-') {
      if (!clearWhenUnresolved) {
        return;
      }
      setState(() {
        if (billing) {
          _stateBControl.text = '-';
        } else {
          _stateDControl.text = '-';
        }
      });
      return;
    }

    setState(() {
      if (billing) {
        _stateBControl.text = normalizedResolvedState;
        if (_isItaly(_countryBId)) {
          _cityBControl.text = appendItalianProvinceAbbreviationToCity(
            city: _cityBControl.text,
            administrativeUnit: _stateBControl.text,
          );
        } else if (_isUSA(_countryBId)) {
          _cityBControl.text = appendUSStateAbbreviationToCity(
            city: _cityBControl.text,
            administrativeUnit: _stateBControl.text,
          );
        }
      } else {
        _stateDControl.text = normalizedResolvedState;
        if (_isItaly(_countryDId)) {
          _cityDControl.text = appendItalianProvinceAbbreviationToCity(
            city: _cityDControl.text,
            administrativeUnit: _stateDControl.text,
          );
        } else if (_isUSA(_countryDId)) {
          _cityDControl.text = appendUSStateAbbreviationToCity(
            city: _cityDControl.text,
            administrativeUnit: _stateDControl.text,
          );
        }
      }
    });
  }

  void _maybeUpdateItalianStateOnCityChanged({
    required bool billing,
    required String value,
  }) {
    final countryId = billing ? _countryBId : _countryDId;
    if (!_isItaly(countryId)) {
      return;
    }

    if (value.trim().length < 2) {
      return;
    }

    _updateStateFromCountryAndPostalCode(billing: billing);
  }

  Future<String?> _resolveAustralianStateFromNominatim({
    required String postalCode,
    required String city,
  }) async {
    final normalizedPostalCode = postalCode.trim();
    final normalizedCity = city.trim();
    if (normalizedPostalCode.isEmpty && normalizedCity.isEmpty) {
      return null;
    }

    final params = <String, String>{
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
      'countrycodes': 'au',
    };
    if (normalizedPostalCode.isNotEmpty) {
      params['postalcode'] = normalizedPostalCode;
    }
    if (normalizedCity.isNotEmpty) {
      params['city'] = normalizedCity;
    }

    var results = await _nominatimSearch(params);
    if (results.isEmpty && normalizedCity.isNotEmpty) {
      final paramsWithoutCity = Map<String, String>.from(params)..remove('city');
      results = await _nominatimSearch(paramsWithoutCity);
    }
    if (results.isEmpty) {
      return null;
    }

    final first = results.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final address = first['address'];
    if (address is! Map<String, dynamic>) {
      return null;
    }

    final stateFull = address['state']?.toString().trim() ?? '';
    final isoRaw = address['ISO3166-2-lvl4']?.toString().trim() ?? '';
    final isoShort = isoRaw.contains('-') ? isoRaw.split('-').last.trim() : isoRaw;

    final mergedState =
        isoShort.isEmpty
            ? stateFull
            : (stateFull.isEmpty ? isoShort : '$isoShort - $stateFull');

    final resolved = resolveAustralianStateAdministrativeUnit(
      countryCode: 'au',
      currentState: mergedState,
      city: normalizedCity,
    );
    return resolved == '-' ? null : resolved;
  }

  Future<String?> _resolveItalianStateFromNominatim({
    required String postalCode,
    required String city,
  }) async {
    final normalizedPostalCode = postalCode.trim();
    final normalizedCity = city.trim();
    if (normalizedPostalCode.isEmpty && normalizedCity.isEmpty) {
      return null;
    }

    final params = <String, String>{
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
      'countrycodes': 'it',
    };
    if (normalizedPostalCode.isNotEmpty) {
      params['postalcode'] = normalizedPostalCode;
    }
    if (normalizedCity.isNotEmpty) {
      params['city'] = normalizedCity;
    }

    final results = await _nominatimSearch(params);
    if (results.isEmpty) {
      return null;
    }

    final first = results.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final address = first['address'];
    if (address is! Map<String, dynamic>) {
      return null;
    }

    final isoRaw =
        address['ISO3166-2-lvl6']?.toString().trim() ??
        address['ISO3166-2-lvl4']?.toString().trim() ??
        '';
    final isoShort = isoRaw.contains('-') ? isoRaw.split('-').last.trim() : isoRaw;

    final county = address['county']?.toString().trim() ?? '';
    final stateDistrict = address['state_district']?.toString().trim() ?? '';
    final cityCandidate =
        normalizedCity.isNotEmpty
            ? normalizedCity
            : (county.isNotEmpty ? county : stateDistrict);

    var resolved = resolveItalianBillingProvince(
      countryCode: 'it',
      currentState: isoShort,
      city: cityCandidate,
    );

    if (resolved == '-') {
      resolved = resolveItalianBillingProvince(
        countryCode: 'it',
        currentState: county,
        city: cityCandidate,
      );
    }

    if (resolved == '-') {
      return null;
    }
    return resolved;
  }

  Future<String?> _resolveSwissStateFromNominatim({
    required String postalCode,
    required String city,
  }) async {
    final normalizedPostalCode = postalCode.trim();
    final normalizedCity = city.trim();
    if (normalizedPostalCode.isEmpty && normalizedCity.isEmpty) {
      return null;
    }

    final params = <String, String>{
      'format': 'json',
      'limit': '1',
      'addressdetails': '1',
      'countrycodes': 'ch',
    };
    if (normalizedPostalCode.isNotEmpty) {
      params['postalcode'] = normalizedPostalCode;
    }
    if (normalizedCity.isNotEmpty) {
      params['city'] = normalizedCity;
    }

    var results = await _nominatimSearch(params);
    if (results.isEmpty && normalizedCity.isNotEmpty) {
      final paramsWithoutCity = Map<String, String>.from(params)..remove('city');
      results = await _nominatimSearch(paramsWithoutCity);
    }
    if (results.isEmpty) {
      return null;
    }

    final first = results.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final address = first['address'];
    if (address is! Map<String, dynamic>) {
      return null;
    }

    final stateFull = address['state']?.toString().trim() ?? '';
    final isoRaw = address['ISO3166-2-lvl4']?.toString().trim() ?? '';
    final isoShort = isoRaw.contains('-') ? isoRaw.split('-').last.trim() : isoRaw;
    final mergedState =
        isoShort.isEmpty
            ? stateFull
            : (stateFull.isEmpty ? isoShort : '$isoShort - $stateFull');

    final resolved = resolveSwissCantonAdministrativeUnit(
      countryCode: 'ch',
      currentState: mergedState,
      city: normalizedCity,
    );
    return resolved == '-' ? null : resolved;
  }

  Future<bool> _validateForm() async {
    final cId = _idControl.text.trim();
    final idValidationError = _validateId(cId);
    if (idValidationError != null) {
      _showDialogSnackBar(idValidationError, type: _DialogSnackBarType.validation);
      return false;
    }
    if (_firstNameControl.text.trim().isEmpty) {
      _showDialogSnackBar('Vorname erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (!_firstNameControl.text.trim().replaceAll(' ', '').split('').every((c) => RegExp(r'[a-zA-ZÀ-ÖØ-öø-ÿ]').hasMatch(c))) {
      _showDialogSnackBar(
        'Vorname darf nur Buchstaben und Leerzeichen enthalten.',
        type: _DialogSnackBarType.validation,
      );
      return false;
    }
    if (_lastNameControl.text.trim().isEmpty) {
      _showDialogSnackBar('Nachname erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (!_lastNameControl.text.trim().replaceAll(' ', '').split('').every((c) => RegExp(r"[a-zA-ZÀ-ÖØ-öø-ÿ'’]").hasMatch(c))) {
      _showDialogSnackBar(
        'Nachname darf nur Buchstaben, Leerzeichen und Apostroph enthalten.',
        type: _DialogSnackBarType.validation,
      );
      return false;
    }
    if (_streetBControl.text.trim().isEmpty) {
      _showDialogSnackBar('Straße (Rechnungsadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_streetBControl.text.trim().length < 2) {
      _showDialogSnackBar('Straßenname ist zu kurz.', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_postalCodeBControl.text.trim().isEmpty) {
      _showDialogSnackBar('PLZ (Rechnungsadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_cityBControl.text.trim().isEmpty) {
      _showDialogSnackBar('Stadt (Rechnungsadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    {
      final city = _cityBControl.text.trim();
      final stripped = city.replaceAll(RegExp(r'[\s\-/(),]'), '');
      if (city.length < 2 || !RegExp(r'^[\p{L}]+$', unicode: true).hasMatch(stripped)) {
        _showDialogSnackBar(
          'Stadt (Rechnungsadresse) muss mindestens 2 Buchstaben enthalten und darf Buchstaben sowie Leerzeichen, Bindestrich, Schraegstrich, Komma und Klammern enthalten.',
          type: _DialogSnackBarType.validation,
        );
        return false;
      }
    }
    if (_countryBId == null) {
      _showDialogSnackBar('Land (Rechnungsadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_isGermany(_countryBId)) {
      final billingState = await _resolveGermanState(_postalCodeBControl.text);
      if (billingState == null) {
        if (!mounted) {
          return false;
        }
        _showDialogSnackBar(
          'Bitte eine gültige PLZ für die Rechnungsadresse eingeben.',
          type: _DialogSnackBarType.validation,
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
        _cityBControl.text = appendUSStateAbbreviationToCity(
          city: _cityBControl.text,
          administrativeUnit: _stateBControl.text,
        );
      }
    } else if (_isItaly(_countryBId)) {
      _stateBControl.text = resolveItalianBillingProvince(
        countryCode: _countryBId,
        currentState: _stateBControl.text,
        city: _cityBControl.text,
      );
      _cityBControl.text = appendItalianProvinceAbbreviationToCity(
        city: _cityBControl.text,
        administrativeUnit: _stateBControl.text,
      );
    } else if (_isAustralia(_countryBId)) {
      final billingState = await _resolveAustralianStateFromNominatim(
        postalCode: _postalCodeBControl.text,
        city: _cityBControl.text,
      );
      if (!mounted) {
        return false;
      }
      if (billingState != null && billingState.isNotEmpty) {
        _stateBControl.text = billingState;
      }
    } else if (_isSwitzerland(_countryBId)) {
      final billingState = await _resolveSwissStateFromNominatim(
        postalCode: _postalCodeBControl.text,
        city: _cityBControl.text,
      );
      if (!mounted) {
        return false;
      }
      if (billingState != null && billingState.isNotEmpty) {
        _stateBControl.text = billingState;
      } else {
        _stateBControl.text = resolveSwissCantonAdministrativeUnit(
          countryCode: _countryBId,
          currentState: _stateBControl.text,
          city: _cityBControl.text,
        );
      }
    } else {
      _stateBControl.text = '-';
    }
    if (_streetDControl.text.trim().isEmpty) {
      _showDialogSnackBar('Straße (Lieferadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_postalCodeDControl.text.trim().isEmpty) {
      _showDialogSnackBar('PLZ (Lieferadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_cityDControl.text.trim().isEmpty) {
      _showDialogSnackBar('Stadt (Lieferadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    {
      final city = _cityDControl.text.trim();
      final stripped = city.replaceAll(RegExp(r'[\s\-/(),]'), '');
      if (city.length < 2 || !RegExp(r'^[\p{L}]+$', unicode: true).hasMatch(stripped)) {
        _showDialogSnackBar(
          'Stadt (Lieferadresse) muss mindestens 2 Buchstaben enthalten und darf Buchstaben sowie Leerzeichen, Bindestrich, Schraegstrich, Komma und Klammern enthalten.',
          type: _DialogSnackBarType.validation,
        );
        return false;
      }
    }
    if (_countryDId == null) {
      _showDialogSnackBar('Land (Lieferadresse) erforderlich', type: _DialogSnackBarType.validation);
      return false;
    }
    if (_isGermany(_countryDId)) {
      final deliveryState = await _resolveGermanState(_postalCodeDControl.text);
      if (deliveryState == null) {
        if (!mounted) {
          return false;
        }
        _showDialogSnackBar(
          'Bitte eine gültige PLZ für die Lieferadresse eingeben.',
          type: _DialogSnackBarType.validation,
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
        _cityDControl.text = appendUSStateAbbreviationToCity(
          city: _cityDControl.text,
          administrativeUnit: _stateDControl.text,
        );
      }
    } else if (_isItaly(_countryDId)) {
      _stateDControl.text = resolveItalianBillingProvince(
        countryCode: _countryDId,
        currentState: _stateDControl.text,
        city: _cityDControl.text,
      );
      _cityDControl.text = appendItalianProvinceAbbreviationToCity(
        city: _cityDControl.text,
        administrativeUnit: _stateDControl.text,
      );
    } else if (_isAustralia(_countryDId)) {
      final deliveryState = await _resolveAustralianStateFromNominatim(
        postalCode: _postalCodeDControl.text,
        city: _cityDControl.text,
      );
      if (!mounted) {
        return false;
      }
      if (deliveryState != null && deliveryState.isNotEmpty) {
        _stateDControl.text = deliveryState;
      }
    } else if (_isSwitzerland(_countryDId)) {
      final deliveryState = await _resolveSwissStateFromNominatim(
        postalCode: _postalCodeDControl.text,
        city: _cityDControl.text,
      );
      if (!mounted) {
        return false;
      }
      if (deliveryState != null && deliveryState.isNotEmpty) {
        _stateDControl.text = deliveryState;
      } else {
        _stateDControl.text = resolveSwissCantonAdministrativeUnit(
          countryCode: _countryDId,
          currentState: _stateDControl.text,
          city: _cityDControl.text,
        );
      }
    } else {
      _stateDControl.text = '-';
    }
    final mail = _mailControl.text.trim();
    if (mail.isNotEmpty && mail != '-') {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(mail)) {
        _showDialogSnackBar('Bitte eine gültige E-Mail-Adresse eingeben.', type: _DialogSnackBarType.validation);
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
      cLon: double.tryParse(_longControl.text.trim()) ?? 0,
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
        _buildCupertinoField(
          label: '℅',
          controller: billing ? _careofBControl : _careofDControl,
          focusNode: billing ? _careofBFocusNode : _careofDFocusNode,
        ),
        const SizedBox(height: 12),
        _buildCupertinoField(
          label: 'Straße (erforderlich)',
          controller: billing ? _streetBControl : _streetDControl,
          focusNode: billing ? _streetBFocusNode : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildCupertinoField(
                label: 'Hausnr.',
                controller: billing ? _houseNumberBControl : _houseNumberDControl,
                focusNode: billing ? _houseNumberBFocusNode : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _buildCupertinoField(
                label: 'PLZ (erforderlich)',
                controller: billing ? _postalCodeBControl : _postalCodeDControl,
                focusNode: billing ? _postalCodeBFocusNode : _postalCodeDFocusNode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildCupertinoField(
          label: 'Stadt (erforderlich)',
          controller: billing ? _cityBControl : _cityDControl,
          focusNode: billing ? _cityBFocusNode : null,
          onChanged: (value) => _maybeUpdateItalianStateOnCityChanged(
            billing: billing,
            value: value,
          ),
        ),
        const SizedBox(height: 12),
        _buildCupertinoField(
          label: 'Verwaltungseinheit',
          controller: billing ? _stateBControl : _stateDControl,
          focusNode: billing ? _stateBFocusNode : _stateDFocusNode,
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
                    _resolveItalianStateInControllers(billing: true);
                    _resolveItalianStateInControllers(billing: false);
                    _resolveUSStateInControllers(billing: true);
                    _resolveUSStateInControllers(billing: false);
                  });
                  _updateStateFromCountryAndPostalCode(
                    billing: true,
                    clearWhenUnresolved: true,
                  );
                  _updateStateFromCountryAndPostalCode(
                    billing: false,
                    clearWhenUnresolved: true,
                  );
                }
              : (v) {
                  setState(() {
                    _countryDId = v;
                    _resolveItalianStateInControllers(billing: false);
                    _resolveUSStateInControllers(billing: false);
                  });
                  _updateStateFromCountryAndPostalCode(
                    billing: false,
                    clearWhenUnresolved: true,
                  );
                },
        ),
      ],
    );
  }

  Widget _buildCupertinoField({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    bool enabled = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    int maxLines = 1,
    bool alignLabelWithHint = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: colorScheme.onSurface,
        );
    final fillColor = enabled
        ? CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context)
        : CupertinoColors.systemGrey5.resolveFrom(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: titleStyle),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          maxLines: maxLines,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: alignLabelWithHint ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: CupertinoColors.systemGrey4.resolveFrom(context),
              width: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 700;
    final isCompact = screenSize.width < 480;
    final title = _isEditing ? 'Kunde bearbeiten' : 'Neuer Kunde';
    final horizontalSnackBarPadding = isCompact ? 10.0 : 16.0;
    final topSnackBarPadding = isCompact ? 8.0 : 12.0;
    final topSnackBarBottomMargin =
        (screenSize.height * (isWide ? 0.72 : 0.66)).clamp(240.0, 640.0).toDouble();

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
      child: Theme(
          data: Theme.of(context).copyWith(
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
              ),
              contentTextStyle: Theme.of(context).textTheme.bodyMedium,
              insetPadding: EdgeInsets.fromLTRB(
                horizontalSnackBarPadding,
                topSnackBarPadding,
                horizontalSnackBarPadding,
                topSnackBarBottomMargin,
              ),
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ConstrainedBox(
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
                    _buildCupertinoField(
                      label: 'ID (erforderlich)',
                      controller: _idControl,
                      enabled: !_isEditing,
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Vorname (erforderlich)',
                      controller: _firstNameControl,
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Nachname (erforderlich)',
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
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Firma',
                      controller: _companyControl,
                      focusNode: _companyFocusNode,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Row(
                          children: [
                            CupertinoSwitch(
                              value: _dealer,
                              onChanged: (v) => setState(() => _dealer = v),
                            ),
                            const Text('Reseller'),
                          ],
                        ),
                        Row(
                          children: [
                            CupertinoSwitch(
                              value: _vat,
                              onChanged: (v) => setState(() => _vat = v),
                            ),
                            const Text('keine MwSt'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'VAT-ID',
                      controller: _vatIdControl,
                      focusNode: _vatIdFocusNode,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    addressSection,
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildCupertinoField(
                      label: 'E-Mail',
                      controller: _mailControl,
                      focusNode: _mailFocusNode,
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Telefon',
                      controller: _phoneControl,
                      focusNode: _phoneFocusNode,
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Website',
                      controller: _webControl,
                      focusNode: _webFocusNode,
                    ),
                    const SizedBox(height: 12),
                    _buildCupertinoField(
                      label: 'Social Media',
                      controller: _socialMediaControl,
                      focusNode: _socialMediaFocusNode,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Koordinaten',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    CupertinoButton(
                      onPressed: _isFetchingCoordinates ? null : _fetchCoordinates,
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          _isFetchingCoordinates
                              ? const CupertinoActivityIndicator(radius: 8)
                              : const Icon(CupertinoIcons.location_solid, size: 18),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Koordinaten aus Lieferadresse ermitteln',
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCupertinoField(
                            label: 'Breitengrad (Lat)',
                            controller: _latControl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildCupertinoField(
                            label: 'Längengrad (Long)',
                            controller: _longControl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildCupertinoField(
                      label: 'Notiz',
                      controller: _noteControl,
                      focusNode: _noteFocusNode,
                      maxLines: 4,
                      alignLabelWithHint: true,
                    ),
                    const SizedBox(height: 12),
                    if (_isEditing &&
                        widget.customer?.cLastModified != null &&
                        widget.customer!.cLastModified > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zuletzt geändert',
                            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                          () {
                            final dt = DateTime.fromMillisecondsSinceEpoch(
                                widget.customer!.cLastModified * 1000);
                            return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                          }(),
                          style: const TextStyle(fontSize: 14),
                        ),
                        ],
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
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    CupertinoButton.filled(
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
          ),
        ),
    );
  }
}
