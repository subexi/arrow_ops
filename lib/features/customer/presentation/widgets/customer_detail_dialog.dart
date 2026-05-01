import 'package:flutter/material.dart';

import '../../domain/customer.dart';

class CustomerDetailDialog extends StatelessWidget {
  const CustomerDetailDialog({
    super.key,
    required this.customer,
    this.countryNameByCode = const {},
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final Map<String, String> countryNameByCode;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  bool _isUsaAddress(String? countryCode) {
    final normalized = countryCode?.trim().toLowerCase();
    return normalized == 'us' || normalized == 'usa';
  }

  String _buildStreetLine({
    required String street,
    required String houseNumber,
    required bool isUsa,
  }) {
    if (isUsa) {
      return '${houseNumber.trim()} ${street.trim()}'.trim();
    }
    return '${street.trim()} ${houseNumber.trim()}'.trim();
  }

  String _buildCityLine({
    required String postalCode,
    required String city,
    required bool isUsa,
  }) {
    if (isUsa) {
      return '${city.trim()} ${postalCode.trim()}'.trim();
    }
    return '${postalCode.trim()} ${city.trim()}'.trim();
  }

  String _resolveCountryName(String? countryCode) {
    final normalized = countryCode?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return '-';
    }
    return countryNameByCode[normalized] ?? countryCode!.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final lastNameUpper = customer.cLastName.toUpperCase();
    final isUsaBilling = _isUsaAddress(customer.cCountryBId);
    final isUsaDelivery = _isUsaAddress(customer.cCountryDId);
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 700;

    final billingSection = _buildSection('Rechnungsadresse', [
      _buildField('℅', customer.cCareofB),
      _buildField(
        'Straße',
        _buildStreetLine(
          street: customer.cStreetB,
          houseNumber: customer.cHouseNumberB,
          isUsa: isUsaBilling,
        ),
      ),
      _buildField(
        'Ort',
        _buildCityLine(
          postalCode: customer.cPostalCodeB,
          city: customer.cCityB,
          isUsa: isUsaBilling,
        ),
      ),
      _buildField('Verwaltungseinheit', customer.cStateB),
      _buildField('Land', _resolveCountryName(customer.cCountryBId)),
    ]);

    final deliverySection = _buildSection('Lieferadresse', [
      _buildField('℅', customer.cCareofD),
      _buildField(
        'Straße',
        _buildStreetLine(
          street: customer.cStreetD,
          houseNumber: customer.cHouseNumberD,
          isUsa: isUsaDelivery,
        ),
      ),
      _buildField(
        'Ort',
        _buildCityLine(
          postalCode: customer.cPostalCodeD,
          city: customer.cCityD,
          isUsa: isUsaDelivery,
        ),
      ),
      _buildField('Verwaltungseinheit', customer.cStateD),
      _buildField('Land', _resolveCountryName(customer.cCountryDId)),
    ]);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 60 : 16,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 780 : 480,
          maxHeight: screenSize.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                '$lastNameUpper, ${customer.cFirstName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Allgemein', [
                      _buildField('ID', customer.cId),
                      _buildField('Firma', customer.cCompany),
                      _buildCheckboxField('Reseller', customer.cDealer),
                      _buildCheckboxField('Keine MwSt', customer.cVat),
                      _buildField('VAT-ID', customer.cVatId),
                    ]),
                    const SizedBox(height: 16),
                    if (isWide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: billingSection),
                            const SizedBox(width: 16),
                            const VerticalDivider(),
                            const SizedBox(width: 16),
                            Expanded(child: deliverySection),
                          ],
                        ),
                      )
                    else ...[
                      billingSection,
                      const SizedBox(height: 16),
                      deliverySection,
                    ],
                    const SizedBox(height: 16),
                    _buildSection('Kontakt', [
                      _buildField('E-Mail', customer.cMail),
                      _buildField('Telefon', customer.cPhone),
                    ]),
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
                    child: const Text('Schließen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onEdit();
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Bearbeiten'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(context);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Löschen'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final lastNameUpper = customer.cLastName.toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kunde löschen?'),
        content: Text(
          'Möchten Sie "$lastNameUpper, ${customer.cFirstName}" wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxField(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          IgnorePointer(
            child: Checkbox(
              value: value,
              onChanged: (_) {},
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
