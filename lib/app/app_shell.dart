import 'package:flutter/material.dart';

import '../features/customer/presentation/customer_page.dart';
import '../features/item/presentation/item_catalogue_page.dart';
import 'app_breakpoints.dart';
import 'widgets/module_placeholder_page.dart';

class ArrowOpsShell extends StatefulWidget {
  const ArrowOpsShell({super.key});

  @override
  State<ArrowOpsShell> createState() => _ArrowOpsShellState();
}

class _ArrowOpsShellState extends State<ArrowOpsShell> {
  int _selectedIndex = 0;
  late final List<Widget?> _pages;

  static const List<_ArrowOpsDestination> _destinations = [
    _ArrowOpsDestination(
      label: 'Kunden',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _ArrowOpsDestination(
      label: 'Artikel',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
    _ArrowOpsDestination(
      label: 'Aufträge',
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
    ),
    _ArrowOpsDestination(
      label: 'Rechnungen',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _ArrowOpsDestination(
      label: 'Auswertung',
      icon: Icons.query_stats_outlined,
      selectedIcon: Icons.query_stats,
    ),
    _ArrowOpsDestination(
      label: 'Sync',
      icon: Icons.cloud_sync_outlined,
      selectedIcon: Icons.cloud_sync,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pages = List<Widget?>.filled(_destinations.length, null);
    _pages[_selectedIndex] = _buildPage(_selectedIndex);
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedIndex = index;
      _pages[index] ??= _buildPage(index);
    });
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const CustomerPage(showModuleNavigation: false);
      case 1:
        return const ItemCataloguePage();
      case 2:
        return const ModulePlaceholderPage(
          title: 'Aufträge',
          icon: Icons.assignment_outlined,
          description:
              'Hier entsteht die Auftragsbearbeitung mit Kunden-, Artikel- und Positionsdaten.',
        );
      case 3:
        return const ModulePlaceholderPage(
          title: 'Rechnungen',
          icon: Icons.receipt_long_outlined,
          description:
              'Hier entsteht die Rechnungserstellung auf Grundlage fakturierter Aufträge.',
        );
      case 4:
        return const ModulePlaceholderPage(
          title: 'Auswertung',
          icon: Icons.query_stats_outlined,
          description:
              'Hier entstehen statistische Auswertungen mit Kennzahlen und Diagrammen.',
        );
      case 5:
        return const ModulePlaceholderPage(
          title: 'Sync',
          icon: Icons.cloud_sync_outlined,
          description:
              'Hier entsteht die Übersicht für iCloud-Synchronisation, Status und Konflikte.',
        );
      default:
        return const CustomerPage(showModuleNavigation: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final windowClass = ArrowOpsBreakpoints.of(context);
    final useBottomNavigation = windowClass == ArrowOpsWindowClass.compact;
    final page = IndexedStack(
      index: _selectedIndex,
      children: _pages
          .map((page) => page ?? const SizedBox.shrink())
          .toList(growable: false),
    );

    if (useBottomNavigation) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectDestination,
          destinations: _destinations
              .map(
                (destination) => NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectDestination,
            labelType: windowClass == ArrowOpsWindowClass.expanded
                ? NavigationRailLabelType.all
                : NavigationRailLabelType.selected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(
                Icons.arrow_outward,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: _destinations
                .map(
                  (destination) => NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
                )
                .toList(growable: false),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _ArrowOpsDestination {
  const _ArrowOpsDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
