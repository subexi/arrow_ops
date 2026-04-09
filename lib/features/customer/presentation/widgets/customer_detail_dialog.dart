import 'package:flutter/material.dart';

import '../../domain/customer.dart';

class CustomerDetailDialog extends StatelessWidget {
  const CustomerDetailDialog({
    super.key,
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${customer.cLastName}, ${customer.cFirstName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('Allgemein', [
              _buildField('ID', customer.cId),
              _buildField('Firma', customer.cCompany),
              _buildField('Reseller', customer.cDealer ? 'Ja' : 'Nein'),
              _buildField('MwSt.-Priv.', customer.cVat ? 'Ja' : 'Nein'),
            ]),
            const SizedBox(height: 16),
            _buildSection('Rechnungsadresse', [
              _buildField('Straße', '${customer.cStreetB} ${customer.cHouseNumberB}'),
              _buildField('Ort', '${customer.cPostalCodeB} ${customer.cCityB}'),
              _buildField('Land', customer.cCountryBId ?? '-'),
            ]),
            const SizedBox(height: 16),
            _buildSection('Lieferadresse', [
              _buildField('Straße', '${customer.cStreetD} ${customer.cHouseNumberD}'),
              _buildField('Ort', '${customer.cPostalCodeD} ${customer.cCityD}'),
              _buildField('Land', customer.cCountryDId ?? '-'),
            ]),
            const SizedBox(height: 16),
            _buildSection('Kontakt', [
              _buildField('E-Mail', customer.cMail),
              _buildField('Telefon', customer.cPhone),
            ]),
          ],
        ),
      ),
      actions: [
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
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kunde löschen?'),
        content: Text(
          'Möchten Sie "${customer.cLastName}, ${customer.cFirstName}" wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.',
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
            width: 100,
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
}
