import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomerResultsHeader extends StatelessWidget {
  const CustomerResultsHeader({
    super.key,
    required this.searchText,
    required this.totalCount,
    required this.filteredCount,
    required this.onShowAllLocations,
  });

  final String searchText;
  final int totalCount;
  final int filteredCount;
  final VoidCallback? onShowAllLocations;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            searchText.isEmpty
                ? 'Kundendaten ($totalCount)'
                : 'Kundendaten ($filteredCount von $totalCount)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Tooltip(
          message:
              'Alle Locations der angezeigten Kunden auf einer Karte anzeigen.',
          child: CupertinoButton(
            onPressed: onShowAllLocations,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.map, size: 18),
                SizedBox(width: 8),
                Text('Alle Locations'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
